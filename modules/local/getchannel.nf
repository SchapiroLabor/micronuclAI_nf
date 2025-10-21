process GETCHANNEL {
    tag "$meta.id"
    label 'process_single'

    container "ghcr.io/schapirolabor/micronuclai:main"

    input:
    tuple val(meta), path(image)
    val(dapi_index)

    output:
    tuple val(meta), path("*_DAPI.tiff"), emit: dapi
    path "versions.yml"                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    getchannel.py \\
        --input ${image} \\
        --output ${prefix}_DAPI.tiff \\
        --DAPI_index ${dapi_index} \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        getchannel: \$(getchannel.py --version)
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    echo $args

    touch ${prefix}.tif

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        getchannel: \$(getchannel --version)
    END_VERSIONS
    """
}
