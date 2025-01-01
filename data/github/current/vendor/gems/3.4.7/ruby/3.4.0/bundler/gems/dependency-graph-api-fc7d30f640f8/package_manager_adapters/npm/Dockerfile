FROM node:23

ENV APP_PATH /adapter

RUN mkdir -p $APP_PATH

WORKDIR $APP_PATH

COPY package.json .
COPY package-lock.json .
RUN npm install

COPY wrapper .
COPY lib/ ./lib
COPY test/ ./test
COPY main.js .

ENTRYPOINT ["./wrapper"]
