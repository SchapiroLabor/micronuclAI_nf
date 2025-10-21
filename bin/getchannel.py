#!/usr/bin/env python

import argparse
from argparse import ArgumentParser as AP
from os.path import abspath
import time
import tifffile


def get_args():
    # Script description
    description = """Extract DAPI channel"""

    # Add parser
    parser = argparse.ArgumentParser(description=description, formatter_class=argparse.RawDescriptionHelpFormatter)

    # Sections
    inputs = parser.add_argument_group(title="Required Input", description="Path to required input file")
    inputs.add_argument("--input", dest="input", action="store", required=True, help="File path to multichanel input image.")
    inputs.add_argument("--output", dest="output", action="store", required=True, help="Output image filepath.")
    inputs.add_argument(
        "--DAPI_index",
        dest="dapi_index",
        action="store",
        type=int,
        default=0,
        help="Index of DAPI channel (0-based)",
    )
    inputs.add_argument("--version", action="version", version="0.1.0")
    arg = parser.parse_args()

    # Standardize paths
    arg.input = abspath(arg.input)
    arg.output = abspath(arg.output)
    return arg

def main(args):
    dapi = tifffile.imread( args.input, series=0, level=0, key=int(args.dapi_index) )
    tifffile.imwrite(args.output, dapi)

if __name__ == "__main__":
    # Read in arguments
    args = get_args()

    # Run script
    st = time.time()
    main(args)
    rt = time.time() - st
    print(f"Script finished in {rt // 60:.0f}m {rt % 60:.0f}s")
