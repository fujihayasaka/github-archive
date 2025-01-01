FROM node:20

RUN apt-get -y update && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY . .

RUN npm i

EXPOSE 9000

CMD ["node", "index.mjs"]