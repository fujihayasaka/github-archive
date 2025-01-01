FROM python:3.13.2

ENV APP_PATH /adapter
RUN mkdir -p $APP_PATH
WORKDIR $APP_PATH

RUN apt-get update && apt-get install -y \
  libxml2-dev

COPY requirements.txt .
RUN pip install --target packages -r requirements.txt

COPY wrapper .
COPY lib/ ./lib
COPY test/ ./test

ENTRYPOINT ["./wrapper"]
