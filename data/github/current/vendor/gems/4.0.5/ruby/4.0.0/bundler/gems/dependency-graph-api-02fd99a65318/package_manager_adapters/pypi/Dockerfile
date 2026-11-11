FROM python:3.15.0a7@sha256:ab0b9b5f51871fa645119a0f4a2772857ee4ff5e59c51bc62847c1b30852d9fc

ENV APP_PATH /adapter
RUN mkdir -p $APP_PATH
WORKDIR $APP_PATH

RUN apt-get update && apt-get install -y \
  libxml2-dev

COPY requirements.txt .
RUN pip install --require-hashes --target packages -r requirements.txt

COPY wrapper .
COPY lib/ ./lib
COPY test/ ./test

ENTRYPOINT ["./wrapper"]
