
require 'json'
require 'cgi'

class AnnotatorController < ApplicationController
  layout 'ontology'

  # REST_URI is defined in application_controller.rb
  ANNOTATOR_URI = REST_URI + "/annotator"

  def index
    @semantic_types_for_select = []
    semantic_types = get_semantic_types
    semantic_types.each_pair do |code, label|
      @semantic_types_for_select << ["#{label} (#{code})", code]
    end
    @semantic_types_for_select.sort! {|a,b| a[0] <=> b[0]}
    # TODO: Duplicate the filteredOntologyList for the LinkedData client?
    #ontology_ids = []
    #annotator.ontologies.each {|ont| ontology_ids << ont[:virtualOntologyId]}
    #@annotator_ontologies = DataAccess.getFilteredOntologyList(ontology_ids)
    #@annotator_ontologies = LinkedData::Client::Models::OntologySubmission.all
    @annotator_ontologies = LinkedData::Client::Models::Ontology.all
  end


  def create
    text_to_annotate = params[:text].strip.gsub("\r\n", " ").gsub("\n", " ")
    options = { :ontologies => params[:ontologies] ||= [],
                :max_level => params[:max_level].to_i ||= 0,
                :semanticTypes => params[:semanticTypes] ||= [],
                :mappingTypes => params[:mappingTypes] ||= [],
                # :wholeWordOnly => params[:wholeWordOnly] ||= true,  # service default is true
                # :withDefaultStopWords => params[:withDefaultStopWords] ||= true,  # service default is true
    }
    start = Time.now
    query = ANNOTATOR_URI
    query += "?text=" + CGI.escape(text_to_annotate)
    query += "&max_level=" + options[:max_level].to_s
    query += "&ontologies=" + CGI.escape(options[:ontologies].join(',')) unless options[:ontologies].empty?
    query += "&semanticTypes=" + options[:semanticTypes].join(',') unless options[:semanticTypes].empty?
    query += "&mappingTypes=" + options[:mappingTypes].join(',') unless options[:mappingTypes].empty?
    #query += "&wholeWordOnly=" + options[:wholeWordOnly].to_s unless options[:wholeWordOnly].empty?
    #query += "&withDefaultStopWords=" + options[:withDefaultStopWords].to_s unless options[:withDefaultStopWords].empty?
    annotations = parse_json(query) # See application_controller.rb
    LOG.add :debug, "Retrieved #{annotations.length} annotations: #{Time.now - start}s"
    massage_annotations(annotations, options) unless annotations.empty?
    render :json => annotations
  end


private


  def massage_annotations(annotations, options)
    # Get the class details required for display, assume this is necessary
    # for every element of the annotations array because the API returns a set.
    # Use the batch REST API to get all the annotated class prefLabels.
    classDetails = get_class_details(annotations, options[:semanticTypes])
    start = Time.now
    annotations2delete = []
    annotations.each do |a|
      ac_id = a['annotatedClass']['id']
      details = classDetails[ac_id]
      if details.nil?
        LOG.add :debug, "Failed to get class details for: #{a['annotatedClass']['links']['self'] }"
        annotations2delete.push(ac_id)
      else
        # Replace the annotated class with simplified details.
        a['annotatedClass'] = details
        hierarchy2delete = []
        a['hierarchy'].each do |h|
          hc_id = h['annotatedClass']['id']
          details = classDetails[hc_id]
          if details.nil?
            LOG.add :debug, "Failed to get class details for: #{h['annotatedClass']['links']['self']}"
            hierarchy2delete.push(hc_id)
          else
            # Replace the annotated class with simplified details.
            h['annotatedClass'] = details
          end
        end
        # Remove any hierarchy classes that fail to resolve details.
        a['hierarchy'].delete_if { |h| hierarchy2delete.include? h['annotatedClass']['id'] }
      end
    end
    # Remove any annotations with annotated classes that fail to resolve details.
    annotations.delete_if { |a| annotations2delete.include? a['annotatedClass']['id'] }
    LOG.add :debug, "Completed annotation modifications: #{Time.now - start}s"
  end


  def get_class_details(annotations, semanticTypes)
    # Use batch service to get class prefLabels
    semantic_types = get_semantic_types   # method in application_controller.rb
    classDetails = {}
    classList = []
    annotations.each do |a|
      cls_id = a['annotatedClass']['id']
      ont_id = a['annotatedClass']['links']['ontology']
      classList.push({'class'=>cls_id, 'ontology'=>ont_id})
      a['hierarchy'].each do |h|
        hc_id = h['annotatedClass']['id']
        classList.push({'class'=>hc_id, 'ontology'=>ont_id}) # must be same ontology for hierarchy
      end
    end
    # remove duplicates
    classSet = classList.to_set # get unique class:ontology set
    classList = classSet.to_a   # assume collection requires a list in batch call
    # make the batch call
    properties = (semanticTypes.empty? && 'prefLabel') || 'prefLabel,semanticType'
    call_params = {'http://www.w3.org/2002/07/owl#Class'=>{'collection'=>classList, 'include'=>properties}}
    response = get_batch_results(call_params)  # method in application_controller.rb
    # Simplify the response data for the UI
    classResults = JSON.parse(response)
    classResults["http://www.w3.org/2002/07/owl#Class"].each do |cls|
      ont_details = get_ontology_details( cls['links']['ontology'] )  # method in application_controller.rb
      next if ont_details.nil? # No display for annotations on any class outside the BioPortal ontology set.
      id = cls['id']
      classDetails[id] = {
          'id' => id,
          'ui' => cls['links']['ui'],
          'uri' => cls['links']['self'],
          'prefLabel' => cls['prefLabel'],
          'ontology' => ont_details,
      }
      unless semanticTypes.empty? || cls['semanticType'].nil?
        # Extract the semantic type descriptions that were requested.
        semanticTypeURI = 'http://bioportal.bioontology.org/ontologies/umls/sty/'
        semanticCodes = cls['semanticType'].map {|t| t.sub( semanticTypeURI, '') }
        requestedCodes = semanticCodes.map {|code| (semanticTypes.include? code and code) || nil }.compact
        requestedDescriptions = requestedCodes.map {|code| semantic_types[code] }.compact
        classDetails[id]['semanticType'] = requestedDescriptions
      else
        classDetails[id]['semanticType'] = []
      end
    end
    return classDetails
  end


  # TODO: Use this method to highlight matched terms in the annotation text.  Currently done in JS on the client.
  def highlight_and_get_context(text, position, words_to_keep = 4)
    # Process the highlighted text
    highlight = ["<span style='color: #006600; padding: 2px 0; font-weight: bold;'>", "", "</span>"]
    highlight[1] = text.utf8_slice(position[0] - 1, position[1] - position[0] + 1)
    # Use scan to split the text on spaces while keeping the spaces
    scan_filter = Regexp.new(/[ ]+?[-\?'"\+\.,]+\w+|[ ]+?[-\?'"\+\.,]+\w+[-\?'"\+\.,]|\w+[-\?'"\+\.,]+|[ ]+?\w+/)
    before = text.utf8_slice(0, position[0] - 1).match(/(\s+\S+|\S+\s+){0,4}$/).to_s
    after = text.utf8_slice(position[1], ActiveSupport::Multibyte::Chars.new(text).length - position[1]).match(/^(\S+\s+\S+|\s+\S+|\S+\s+){0,4}/).to_s
    # The process above will not keep a space right before the highlighted word, so let's keep it here if needed
    # 32 is the character code for space
    kept_space = text.utf8_slice(position[0] - 2) == " " ? " " : ""
    # Put it all together
    [before, kept_space, highlight.join, after].join
  end


end

