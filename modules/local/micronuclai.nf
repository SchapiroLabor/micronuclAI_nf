process MICRONUCLAI_PREDICT {
    tag "$meta.id"
    label 'process_single'

    container "ghcr.io/schapirolabor/micronuclai:main"

    input:
    tuple val(meta), path(image), path(mask)

    output:
    tuple val(meta), path("*_predictions.csv"), emit: predictions
    tuple val(meta), path("*_summary.csv")    , emit: stats
    path "versions.yml"                       , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args    = task.ext.args   ?: ''
    def prefix  = task.ext.prefix ?: "${meta.id}"
    def VERSION = '0.0.1'
    """
    python /micronuclAI/src/model/prediction2.py \\
        -i $image \\
        -m $mask \\
        -mod /micronuclAI/micronuclAI_model/micronuclai.pt \\
        -o . \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        micronuclAI: ${VERSION}
    END_VERSIONS
    """

    stub:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def VERSION = '0.0.1'
    """
    touch ${prefix}_predictions.csv
    touch ${prefix}_summary.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        micronuclAI: ${VERSION}
    END_VERSIONS
    """
}
