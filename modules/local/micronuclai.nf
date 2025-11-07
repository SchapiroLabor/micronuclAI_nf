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
    def VERSION = '1.0.0'
    """
    PYTHONPATH=/micronuclAI python -m src.model.micronuclai_predict \\
        -i $image \\
        -m $mask \\
        -mod /micronuclAI/models/micronuclai.pt \\
        -o . \\
        $args

    mv cell_predictions.csv ${prefix}_cell_predictions.csv
    mv cell_summary.csv ${prefix}_cell_summary.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        micronuclAI: ${VERSION}
    END_VERSIONS
    """

    stub:
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
