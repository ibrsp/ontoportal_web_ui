# frozen_string_literal: true

class ChangeRequestsController < ApplicationController
  before_action :require_login, except: [:create]

  def create_synonym
    @concept_label = params[:concept_label]
    @concept_id = params[:concept_id]
    @ont_acronym = params[:ont_acronym]
    @username = session[:user].username

    respond_to :js
  end

  def remove_synonym
    @concept_id = params[:concept_id]
    @concept_label = params[:concept_label]
    @concept_synonyms = params[:concept_synonyms].sort! { |a, b| a.downcase <=> b.downcase }
    @ont_acronym = params[:ont_acronym]
    @username = session[:user].username

    respond_to :js
  end

  def create
    params[:curie] = generate_curie(params[:ont_acronym], params[:concept_id])
    params[:content] = KGCL::IssueContentGenerator.call(params)
    @issue = IssueCreatorService.call(params)
    flash.now.notice = helpers.change_request_success_message if @issue['id'].present?

    respond_to :js
  end

  private

  def generate_curie(ont_acronym, concept_id)
    ontology = LinkedData::Client::Models::Ontology.find_by_acronym(ont_acronym).first
    query_string = { display: 'notation,prefixIRI', display_links: false, display_context: false }
    concept = ontology.explore.single_class(query_string, concept_id)

    if concept.notation
      concept.notation
    elsif concept.prefixIRI
      concept.prefixIRI
    else
      concept_id
    end
  end

  def require_login
    if session[:user].blank?
      # TODO: Can this implementation be improved? For discussion:
      #   https://stackoverflow.com/a/18681807
      #   https://stackoverflow.com/a/10607511
      #   https://stackoverflow.com/a/51275445
      render js: "window.location.href='#{login_index_path}'"
    end
  end
end
