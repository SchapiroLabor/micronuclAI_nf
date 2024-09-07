/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// local modules
include { MICRONUCLAI_PREDICT    } from '../modules/local/micronuclai'

// nf-core modules
include { CELLPOSE               } from '../modules/nf-core/cellpose/main'
include { DEEPCELL_MESMER        } from '../modules/nf-core/deepcell/mesmer/main'
include { STARDIST               } from '../modules/nf-core/stardist/main'
include { MULTIQC                } from '../modules/nf-core/multiqc/main'

// plugins and utils
include { paramsSummaryMap       } from 'plugin/nf-validation'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_micronuclai_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow MICRONUCLAI {

    take:
    ch_samplesheet // channel: samplesheet read in from --input

    main:

    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    //
    // SECTION: run segmentation
    //
    if (!params.skip_segmentation){
        segmentation_out = Channel.empty()

        //
        // MODULE: Run CELLPOSE
        //
        CELLPOSE(
            ch_samplesheet,
            params.cellpose_custom_model ? Channel.fromPath(params.cellpose_custom_model) : []
        )
        ch_versions = ch_versions.mix(CELLPOSE.out.versions)
        segmentation_out = segmentation_out.mix(CELLPOSE.out.mask)
        //}
        //
        // MODULE: Run STARDIST
        //
        STARDIST(
            ch_samplesheet
        )
        ch_versions = ch_versions.mix(STARDIST.out.versions)
        segmentation_out = segmentation_out.mix(STARDIST.out.mask)
        //
        // MODULE: Run DEEPCELL_MESMER
        //
        DEEPCELL_MESMER(
            ch_samplesheet,
            [[:],[]]
        )
        ch_versions = ch_versions.mix(DEEPCELL_MESMER.out.versions)
        segmentation_out = segmentation_out.mix(DEEPCELL_MESMER.out.mask)
        ch_samplesheet
            .join( segmentation_out )
            .set { micronuclAI_in }
    }
    else{
        ch_samplesheet
            .set { micronuclAI_in }
    }
    //
    // MODULE: Run micronuclAI
    //
    MICRONUCLAI_PREDICT(micronuclAI_in)
    ch_versions = ch_versions.mix(MICRONUCLAI_PREDICT.out.versions)

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_pipeline_software_mqc_versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }

    //
    // MODULE: MultiQC
    //
    ch_multiqc_config        = Channel.fromPath(
        "$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config = params.multiqc_config ?
        Channel.fromPath(params.multiqc_config, checkIfExists: true) :
        Channel.empty()
    ch_multiqc_logo          = params.multiqc_logo ?
        Channel.fromPath(params.multiqc_logo, checkIfExists: true) :
        Channel.empty()

    summary_params      = paramsSummaryMap(
        workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary = Channel.value(paramsSummaryMultiqc(summary_params))

    ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
        file(params.multiqc_methods_description, checkIfExists: true) :
        file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = Channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description))

    ch_multiqc_files = ch_multiqc_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true
        )
    )

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        []
    )

    emit:
    multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
