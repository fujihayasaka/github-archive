
if ! command -v tfenv; then 
    git clone --depth=1 https://github.com/tfutils/tfenv.git ~/.tfenv
    sudo ln -s ~/.tfenv/bin/* /usr/local/bin
else
    echo "tfenv already installed"
fi

export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
tfenv install