//
// Subworkflow with functionality specific to the micronuclAI_nf pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { UTILS_NFVALIDATION_PLUGIN } from '../../nf-core/utils_nfvalidation_plugin'
include { paramsSummaryMap          } from 'plugin/nf-validation'
include { fromSamplesheet           } from 'plugin/nf-validation'
include { UTILS_NEXTFLOW_PIPELINE   } from '../../nf-core/utils_nextflow_pipeline'
include { completionEmail           } from '../../nf-core/utils_nfcore_pipeline'
include { completionSummary         } from '../../nf-core/utils_nfcore_pipeline'
include { dashedLine                } from '../../nf-core/utils_nfcore_pipeline'
include { nfCoreLogo                } from '../../nf-core/utils_nfcore_pipeline'
include { imNotification            } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NFCORE_PIPELINE     } from '../../nf-core/utils_nfcore_pipeline'
include { workflowCitation          } from '../../nf-core/utils_nfcore_pipeline'

/*
========================================================================================
    SUBWORKFLOW TO INITIALISE PIPELINE
========================================================================================
*/

workflow PIPELINE_INITIALISATION {

    take:
    version           // boolean: Display version and exit
    help              // boolean: Display help text
    validate_params   // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs   // boolean: Do not use coloured log outputs
    nextflow_cli_args //   array: List of positional nextflow CLI args
    outdir            //  string: The output directory where the results will be saved
    input             //  string: Path to input samplesheet

    main:

    ch_versions = Channel.empty()

    //
    // Print version and exit if required and dump pipeline parameters to JSON file
    //
    UTILS_NEXTFLOW_PIPELINE (
        version,
        true,
        outdir,
        workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1
    )

    //
    // Validate parameters and generate parameter summary to stdout
    //
    pre_help_text = nfCoreLogo(monochrome_logs)
    post_help_text = '\n' + workflowCitation() + '\n' + dashedLine(monochrome_logs)
    def String workflow_command = "nextflow run ${workflow.manifest.name} -profile <docker/singularity/.../institute> --input samplesheet.csv --outdir <OUTDIR>"
    UTILS_NFVALIDATION_PLUGIN (
        help,
        workflow_command,
        pre_help_text,
        post_help_text,
        validate_params,
        "nextflow_schema.json"
    )

    //
    // Check config provided to the pipeline
    //
    UTILS_NFCORE_PIPELINE (
        nextflow_cli_args
    )
    //
    // Custom validation for pipeline parameters
    //
    //validateInputParameters()

    //
    // Create channel from input file provided through params.input
    //
    Channel
        .fromSamplesheet("input")
        .map {
            validateInputSamplesheet(it)
        }
        .set { ch_samplesheet }

    emit:
    samplesheet = ch_samplesheet
    versions    = ch_versions
}

/*
========================================================================================
    SUBWORKFLOW FOR PIPELINE COMPLETION
========================================================================================
*/

workflow PIPELINE_COMPLETION {

    take:
    email           //  string: email address
    email_on_fail   //  string: email address sent on pipeline failure
    plaintext_email // boolean: Send plain-text email instead of HTML
    outdir          //    path: Path to output directory where results will be published
    monochrome_logs // boolean: Disable ANSI colour codes in log output
    hook_url        //  string: hook URL for notifications
    multiqc_report  //  string: Path to MultiQC report

    main:

    summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")

    //
    // Completion email and summary
    //
    workflow.onComplete {
        if (email || email_on_fail) {
            completionEmail(summary_params, email, email_on_fail, plaintext_email, outdir, monochrome_logs, multiqc_report.toList())
        }

        completionSummary(monochrome_logs)

        if (hook_url) {
            imNotification(summary_params, hook_url)
        }
    }

    workflow.onError {
        log.error "Pipeline failed. Please refer to troubleshooting docs: https://nf-co.re/docs/usage/troubleshooting"
    }
}

/*
========================================================================================
    FUNCTIONS
========================================================================================
*/
//
// Check and validate pipeline parameters
//

//def validateInputParameters() {
//    genomeExistsError()
//}

//
// Validate channels from input samplesheet
//

def validateInputSamplesheet(input) {
    def (meta, image, segmentation) = input

    // Check if segmentation mask is provided but skip_segmentation isn't toggled:
    if (params.skip_segmentation) {
        if (!segmentation){
            error("Please add segmentation mask into the samplesheet if params.skip_segmentation = true")
        }
        return input
    }
    else {
        if (segmentation){
            error("Segmentation path is provided, please set params.skip_segmentation to false")
        }
        return [meta, image]
    }
}

def arrangeSummaryFiles(meta, summary_file ){
    def inputSampleName = meta.id // get sample ID
    def outputCsvPath = summary_file.getName().split('\\.')[0] + "_resummarize.csv"

    def lines = summary_file.readLines()
    // Parse the input CSV into a map for easy lookup
    def data = [:]
    lines.each { line ->
        def (key, value) = line.split(',')
        data[key] = value
    }

    // Create the output CSV header
    def header = "sample,total_cells,total_micronuclei,cells_with_micronuclei,cells_with_micronuclei_ratio,micronuclei_ratio,0,1,2,3,4,5_or_more"
    def sample = meta.id
    def totalCells = data['total_cells'] ?: "0"
    def totalMicronuclei = data['total_micronuclei'] ?: "0"
    def cellsWithMicronuclei = data['cells_with_micronuclei'] ?: "0"
    def cellsWithMicronucleiRatio = data['cells_with_micronuclei_ratio'] ?: "0"
    def micronucleiRatio = data['micronuclei_ratio'] ?: "0"

    // Extract counts for specific micronuclei numbers (0, 1 ...)
    def counts = [0, 1, 2, 3, 4].collect { data[it.toString()] ?: "0" } // Count for 0-4
    def moreThan5 = data.findAll { key, value -> key.isInteger() && key.toInteger() >= 5 }
                    .collect { it.value.toFloat() }
                    .sum() ?: 0

    def row = "$sample,$totalCells,$totalMicronuclei,$cellsWithMicronuclei,$cellsWithMicronucleiRatio,$micronucleiRatio,${counts.join(',')},$moreThan5"
    def outputCsv = new File(outputCsvPath)
    outputCsv.text = "$header\n$row"

    return outputCsv
}

def finalizeSummaryFile(csvFile) {
    def lines = csvFile.readLines()  // Read all lines from the file
    def newContent = []
    def outputCsvPath = csvFile.getName().split('\\.')[0] + "_complete.csv"

    // Keep the first row (header)
    newContent << lines[0]

    lines.drop(1).eachWithIndex { line, index ->
        if ((index + 1) % 2 != 0) {  // Only keep even-indexed lines
            newContent << line
        }
    }
    // Extract header and data
    def header = newContent[0]
    def data = newContent.drop(1)
    def sortedData = data.sort { a, b ->
        def aValues = a.split(',')
        def bValues = b.split(',')
        def comparison = aValues[0].compareTo(bValues[0])
        comparison
    }
    def sortedContent = [header] + sortedData

    def outputCsv = new File(outputCsvPath)
    outputCsv.text = sortedContent.join('\n')

    return outputCsv
}

//
// Exit pipeline if incorrect --genome key provided
//
// def genomeExistsError() {
//     if (params.genomes && params.genome && !params.genomes.containsKey(params.genome)) {
//         def error_string = "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n" +
//             "  Genome '${params.genome}' not found in any config files provided to the pipeline.\n" +
//             "  Currently, the available genome keys are:\n" +
//             "  ${params.genomes.keySet().join(", ")}\n" +
//             "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
//         error(error_string)
//     }
// }

//
// Generate methods description for MultiQC
//
def toolCitationText() {
    def citation_text = [
            "Tools used in the workflow included:",
            params.segmentation_method == 'mesmer'   ? "Mesmer (Greenwald et al. 2021),"      : "",
            params.segmentation_method == 'stardist' ? "Stardist (Weigert and Schmidt 2022)," : "",
            params.segmentation_method == 'cellpose' ? "Cellpose (Stringer et al. 2021; Pachitariu et al 2022)," : "",
            "micronuclAI (Ibarra-Arellano et al. 2024),",
            "MultiQC (Ewels et al. 2016)",
            "."
        ].join(' ').trim()

    return citation_text
}

def toolBibliographyText() {
    def reference_text = [
            params.segmentation_method == 'mesmer'   ? "<li>Greenwald, N.F., Miller, G., Moen, E. et al. Whole-cell segmentation of tissue images with human-level performance using large-scale data annotation and deep learning. Nat Biotechnol 40, 555–565 (2022). https://doi.org/10.1038/s41587-021-01094-0</li>"               : "",
            params.segmentation_method == 'stardist' ? "<li>M. Weigert and U. Schmidt, Nuclei Instance Segmentation and Classification in Histopathology Images with Stardist, 2022 IEEE International Symposium on Biomedical Imaging Challenges (ISBIC), Kolkata, India, 2022, pp. 1-4, doi: 10.1109/ISBIC56247.2022.9854534.</li>" : "",
            params.segmentation_method == 'cellpose' ? "<li>Stringer, C., Wang, T., Michaelos, M. et al. Cellpose: a generalist algorithm for cellular segmentation. Nat Methods 18, 100–106 (2021). https://doi.org/10.1038/s41592-020-01018-x</li>"                                                                                 : "",
            "<li>Ibarra-Arellano, M.A., Caprio, L.A., Hada, A. et al. (2024). micronuclAI: Automated quantification of micronuclei for assessment of chromosomal instability. bioRxiv 2024.05.24.595722; doi: https://doi.org/10.1101/2024.05.24.595722</li>",
            "<li>Ewels, P., Magnusson, M., Lundin, S., & Käller, M. (2016). MultiQC: summarize analysis results for multiple tools and samples in a single report. Bioinformatics , 32(19), 3047–3048. doi: /10.1093/bioinformatics/btw354</li>"
        ].join(' ').trim()

    return reference_text
}

def methodsDescriptionText(mqc_methods_yaml) {
    // Convert  to a named map so can be used as with familar NXF ${workflow} variable syntax in the MultiQC YML file
    def meta = [:]
    meta.workflow = workflow.toMap()
    meta["manifest_map"] = workflow.manifest.toMap()

    // Pipeline DOI
    if (meta.manifest_map.doi) {
        // Using a loop to handle multiple DOIs
        // Removing `https://doi.org/` to handle pipelines using DOIs vs DOI resolvers
        // Removing ` ` since the manifest.doi is a string and not a proper list
        def temp_doi_ref = ""
        String[] manifest_doi = meta.manifest_map.doi.tokenize(",")
        for (String doi_ref: manifest_doi) temp_doi_ref += "(doi: <a href=\'https://doi.org/${doi_ref.replace("https://doi.org/", "").replace(" ", "")}\'>${doi_ref.replace("https://doi.org/", "").replace(" ", "")}</a>), "
        meta["doi_text"] = temp_doi_ref.substring(0, temp_doi_ref.length() - 2)
    } else meta["doi_text"] = ""
    meta["nodoi_text"] = meta.manifest_map.doi ? "" : "<li>If available, make sure to update the text to include the Zenodo DOI of version of the pipeline used. </li>"

    // Tool references
    meta["tool_citations"] = ""
    meta["tool_bibliography"] = ""

    meta["tool_citations"] = toolCitationText().replaceAll(", \\.", ".").replaceAll("\\. \\.", ".").replaceAll(", \\.", ".")
    meta["tool_bibliography"] = toolBibliographyText()


    def methods_text = mqc_methods_yaml.text

    def engine =  new groovy.text.SimpleTemplateEngine()
    def description_html = engine.createTemplate(methods_text).make(meta)

    return description_html.toString()
}
