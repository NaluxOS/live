SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Stub for help message if needed in the future
function help() {
    :
}

function parse_options() {
    options=$(getopt -o "h" -l "help" -- "$@")
    
    # Show usage if getopt fails to parse options
    if ! [ $? -eq 0 ]; then
        help
        exit 1
    fi
    
    eval set -- "$options"
    while true; do
        case "$1" in
            -h | --help)
                help
                exit 0
            ;;
            
            --)
                shift
                break
            ;;
        esac
        shift
    done
}

# =============   main  ================
parse_options

# Prepare environment for docker build
rm -rf out/
mkdir out
docker container rm nalux
docker image rm nalux_img
docker build -t nalux_img .

# Build Nalux
docker run --name nalux -v $SCRIPT_DIR/out:/opt/nalux/out --privileged -it nalux_img
