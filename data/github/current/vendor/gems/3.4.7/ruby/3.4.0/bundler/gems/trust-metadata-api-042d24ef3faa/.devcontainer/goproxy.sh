export GOPROXY=https://goproxy.githubapp.com/mod,https://proxy.golang.org/,direct
export GOPRIVATE=
export GONOPROXY=
export GONOSUMDB='github.com/github/*'
echo "machine goproxy.githubapp.com login nobody password $CODESPACES_GITHUB_TOKEN" >> $HOME/.netrc
