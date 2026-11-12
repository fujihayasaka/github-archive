FROM ruby:3.4-slim AS ruby-dev

# create a non-root user
RUN groupadd -g 1000 configsd-ruby && \
    useradd -r -u 1000 -g configsd-ruby configsd-ruby

WORKDIR /workspaces

# Install build tools for native gems
# libyaml is included to support the debug gem
RUN apt-get update && apt-get install -y build-essential libyaml-dev && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY . /workspaces/
