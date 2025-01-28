FROM docker-io.monitorsoft.ru/ruby:3.3.1-slim-bookworm AS base

RUN apt update && apt --fix-missing install -y build-essential pkg-config bash curl libpq-dev openssh-client \
     libpq-dev libsqlite3-dev libssl-dev libgeos-dev\
     && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_21.x | bash - && \
    apt-get install -y nodejs
RUN npm i -g yarn

RUN echo 'gem: --no-document' >> ~/.gemrc
RUN gem install ruby-debug-ide bundler --no-document

WORKDIR /app

COPY .ruby-version Gemfile* /app/
COPY --from=rbase Gemfile *.gemspec ../src_rbase/

RUN bundle install --jobs $(nproc) --retry=3

COPY yarn.loc[k] package.jso[n] /app/
RUN [ -f yarn.lock ] && yarn install ---frozen-lockfile || exit 0

COPY . /app
ENV RACK_ENV=production NODE_ENV=production
RUN rake -T | grep 'rake build' && rake build || echo 'no build task'
RUN rm -rf node_modules

FROM ruby:3.3.1-slim-bookworm AS deploy
RUN apt update && apt install --fix-missing -y bash curl libpq-dev openssh-client \
      libpq-dev sqlite3 libssl-dev libgeos-dev\
     && rm -rf /var/lib/apt/lists/*

RUN echo 'gem: --no-document' >> ~/.gemrc
COPY --from=base /usr/local/bundle /usr/local/bundle
COPY --from=base /app /app
COPY --from=rbase . ../src_rbase

ENV SERVER_ENV=production \
    RACK_ENV=production \
    NODE_ENV=production \
    DOCKER_CONTAINER=true \
    PORT=7000

WORKDIR /app

RUN bundle exec rspec

HEALTHCHECK --interval=15s --timeout=2s --retries=3 --start-period=15m --start-interval=30s CMD curl --fail http://localhost:$PORT/healthcheck || exit 1
CMD echo "Container start" && ls && bundle exec rackup -o 0.0.0.0 -p $PORT -s falcon
