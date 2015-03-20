function wrapupTabChange(selectedTab) {
  jQuery.unblockUI();
  tb_init('a.thickbox, area.thickbox, input.thickbox');
  jQuery(document).trigger("visualize_tab_change", [{tabType: selectedTab}]);
  jQuery(document).trigger("tree_changed");
}

function setCacheCurrent() {
  var currentData = [];

  // Store notes table data
  if (typeof notesTable !== 'undefined' && notesTable !== null && notesTable.length !== 0) {
    currentData["notes_table_data"] = notesTable.fnGetData();
  }

  // Reset the table
  resetNotesTable();

  currentData[0] = jQuery('#visualization_content').html();
  currentData[1] = jQuery('#details_content').html();
  currentData[2] = jQuery('#notes_content').html();
  currentData[3] = jQuery('#mappings_content').html();
  currentData[5] = jQuery('#note_count').html();
  currentData[6] = jQuery('#mapping_count').html();
  setCache(getConcept(), currentData);
}

function resetNotesTable() {
  jQuery(".notes_table_container div[class^=dataTables_]").remove();
}

function insertNotesTable(aData) {
  jQuery(".notes_table_container").append(jQuery("#notes_list_table_clone").clone());
  jQuery(".notes_table_container #notes_list_table_clone").attr("id", "notes_list_table");
  wireTableWithData(jQuery("#notes_list_table"), aData);
}

var simpleTreeCollection;
function initClassTree() {
  simpleTreeCollection = jQuery('.simpleTree').simpleTree({
    autoclose: false,
    drag: false,
    animate: true,
    timeout: 20000,
    afterClick:function(node){
      History.pushState({p:"classes", conceptid:jQuery(node).children("a").attr("id")}, jQuery.bioportal.ont_pages["classes"].page_name + " | " + org_site, jQuery(node).children("a").attr("href"));
    },
    afterAjaxError: function(node){
      simpleTreeCollection[0].option.animate = false;
      simpleTreeCollection.get(0).nodeToggle(node.parent()[0]);
      if (node.parent().children(".expansion_error").length == 0) {
        node.parent().append("<span class='expansion_error'>Error, please try again");
      }
      simpleTreeCollection[0].option.animate = true;
    },
    beforeAjax: function(node){
      node.parent().children(".expansion_error").remove();
    }
  });

  setConcept(jQuery(document).data().bp.ont_viewer.concept_id);
  setOntology(jQuery(document).data().bp.ont_viewer.ontology_id);
  jQuery("#sd_content").scrollTo(jQuery('a.active'));

  // Set the cache for the first concept we retrieved
  setCacheCurrent();

  // Setup the "Get all classes" link for times when the children is greater than our max
  jQuery(".too_many_children_override").live('click', function(event) {
    event.preventDefault();
    var result = jQuery(this).closest("ul");
    result.html("<img src='/images/tree/spinner.gif'>");
    jQuery.ajax({
      url: jQuery(this).attr('href'),
      context: result,
      success: function(data){
        this.html(data);
        // This sets up the returned content with SimpleTree functionality
        simpleTreeCollection.get(0).setTreeNodes(this);
      },
      error: function(){
        this.html("<div style='background: #eeeeee; padding: 5px; width: 80%;'>Problem getting children. <a href='" + jQuery(this).attr('href') + "' class='too_many_children_override'>Try again</a></div>");
      }
    });
  });
};


function nodeClicked(node_id) {
  // Get current html and store data in cache (to account for changes since the cache was retrieved)
  setCacheCurrent();

  // Reset notesTable for next node
  notesTable = null;

  if(node_id == 0){
    alert("Sorry, we cannot display all the classes at this level in the hierarchy because there are too many of them. Please select another class or use the Search to find a specific concept in this ontology");
    return;
  }

  setConcept(node_id);

  // Deal with permalink
  jQuery("#purl_link_container").hide();
  var concept_uri = (node_id.indexOf("http://") == 0 || node_id.indexOf(encodeURIComponent("http://")) == 0 );
  var purl_anchor = concept_uri ? "?conceptid="+node_id : "/"+node_id;
  var selectedTab = jQuery("#bd_content div.tabs li.selected a").attr("href").slice(1);
  jQuery("#purl_input").val(purl_prefix + purl_anchor);

  if (getCache(node_id) != null) {
    var tabData = getCache(node_id);
    var loc;

    // Make the clicked node active
    jQuery("a.active").removeClass("active");
    jQuery(document.getElementById(node_id)).addClass("active");

    jQuery('#visualization_content').html(tabData[0]);
    jQuery('#details_content').html(tabData[1]);
    jQuery('#notes_content').html(tabData[2]);
    jQuery('#mappings_content').html(tabData[3]);
    jQuery('#note_count').html(tabData[5]);
    jQuery('#mapping_count').html(tabData[6]);

    // Insert notes table
    insertNotesTable(tabData["notes_table_data"]);

    wrapupTabChange(selectedTab);
  } else {
    jQuery.blockUI({ message: '<h1><img src="/images/tree/spinner.gif" /> Loading Class...</h1>', showOverlay: false });
    jQuery.get('/ajax_concepts/'+jQuery(document).data().bp.ont_viewer.ontology_id+'/?conceptid='+node_id+'&callback=load',
      function(data){
        var tabData = data.split("|||");
        var loc;

        // the tabs
        jQuery('#visualization_content').html(tabData[0]);
        jQuery('#details_content').html(tabData[1]);
        jQuery('#notes_content').html(tabData[2]);
        jQuery('#mappings_content').html(tabData[3]);
        jQuery('#note_count').html(tabData[5]);
        jQuery('#mapping_count').html(tabData[6]);

        // Load the resource index
        if (selectedTab == "resource_index") {
          callTab('resource_index', '/resource_index/resources_table?conceptids='+jQuery(document).data().bp.ont_viewer.ontology_id+'/'+encodeURIComponent(getConcept()));
        }

        setCache(node_id,tabData);
        wrapupTabChange(selectedTab);
      }
    );
  }

}

// Keep trying to put the tree view content in place (looks for #sd_content)
function placeTreeView(treeHTML) {
  if (jQuery("#sd_content").length == 0) {
    setTimeout(function(){placeTreeView(treeHTML)}, 500);
  } else {
    document.getElementById("sd_content").innerHTML = treeHTML;
    initClassTree();
  }
}

// Retrieve the tree view using ajax
function getTreeView() {
  jQuery.ajax({
    url: "/ajax/classes/treeview?ontology="+jQuery(document).data().bp.ont_viewer.ontology_id+"&conceptid="+encodeURIComponent(jQuery(document).data().bp.ont_viewer.concept_id),
    success: function(data) {
      placeTreeView(data);
    },
    error: function(data) {
      jQuery.get("/ajax/classes/treeview?ontology="+jQuery(document).data().bp.ont_viewer.ontology_id+"&conceptid=root", function(data){
        var rootTree = "<div class='tree_error'>Displaying the path to this class has taken too long. You can browse classes below.</div>" + data;
        placeTreeView(rootTree);
      });
    },
    timeout: 15000
  });
}

// Get the treeview using ajax
// We do this right after writing #sd_content to the dom to make sure it loads before other async portions of the page
jQuery(document).ready(function(){
  getTreeView();
});
