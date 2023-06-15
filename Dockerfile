FROM node:18.16-alpine3.17

ENV LANG C.UTF-8
ENV TZ Asia/Tokyo

WORKDIR /app

RUN apk update && \
  apk upgrade && \
  apk add --no-cache

COPY package.json tsconfig.json yarn.lock ./

RUN yarn

ENV HOST 0.0.0.0
EXPOSE 5173
