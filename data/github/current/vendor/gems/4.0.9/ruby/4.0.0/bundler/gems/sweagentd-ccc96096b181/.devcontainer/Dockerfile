FROM mcr.microsoft.com/devcontainers/python:3-3.12-bookworm

# NVM is already in this image, so just set up node 20 and the Azure Functions Core Tools
RUN su vscode -c "\
    source /usr/local/share/nvm/nvm.sh && \
    nvm install 20"
