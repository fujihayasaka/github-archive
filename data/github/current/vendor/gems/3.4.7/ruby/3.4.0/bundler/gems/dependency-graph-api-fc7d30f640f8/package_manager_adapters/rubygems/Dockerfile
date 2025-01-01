FROM ruby:3.3.6-slim

# Update our apt repositories and install dependencies for dependency-graph-api
#   NOTE: Please do not add dependencies that are required by a single Package Manager Adapter here, instead
#         add them in a dedicated `RUN apt-get install` in their relevant section of the Dockerfile.
RUN apt-get update && \
  apt-get install -y cmake pkg-config build-essential  libicu-dev patch ruby-dev zlib1g-dev liblzma-dev libpq-dev git vim

# Debian slim-stretch excludes man-pages, but update-alternatives
# doesn't respect the dpkg-specific configuration used to do this.
# We have to re-create the /usr/share/man* directories to install Java
RUN mkdir -p /usr/share/man/man1/ /usr/share/man/man3/ /usr/share/man/man7/

RUN apt-get install -y postgresql-15
RUN service postgresql start

USER postgres

RUN service postgresql start &&\
  createuser --superuser root

RUN echo local all all md5 >> /etc/postgresql/15/main/pg_hba.conf
RUN echo "listen_addresses = ''" >> /etc/postgresql/15/main/postgresql.conf

USER root

ENV APP_PATH /adapter

RUN mkdir -p $APP_PATH

WORKDIR $APP_PATH

COPY Gemfile .
COPY Gemfile.lock .
RUN bundle install

COPY wrapper .
COPY lib/ ./lib
COPY test/ ./test
COPY run.rb .

ENTRYPOINT ["./wrapper"]
