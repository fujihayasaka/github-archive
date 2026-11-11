FROM node:24@sha256:80fc934952c8f1b2b4d39907af7211f8a9fff1a4c2cf673fb49099292c251cec

ENV APP_PATH /adapter

RUN mkdir -p $APP_PATH

WORKDIR $APP_PATH

COPY package.json .
COPY package-lock.json .
RUN npm ci

COPY wrapper .
COPY lib/ ./lib
COPY test/ ./test
COPY main.js .

ENTRYPOINT ["./wrapper"]
