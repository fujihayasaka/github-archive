# Do not run directly! Source this from scripts here that should be
# run inside the development Docker container by default. You can do
# this robustly using:
#
#     DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
#     . "$DIR/ensure-devcontainer.sh"

if [ -z ${IN_TURBOSCAN_DEVCONTAINER-} ]; then
    exec "$DIR"/dev-run script/"$( basename "$0")" "$@"
fi
