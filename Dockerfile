# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.4.5
ARG BUNDLER_VERSION=2.7.1
FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim as base
ARG BUNDLER_VERSION
ARG RAILS_MASTER_KEY
ARG DATABASE_URL
ARG CACHE_DATABASE_URL
ARG QUEUE_DATABASE_URL
ARG RAILS_ENV

# Rails app lives here
WORKDIR /rails

# Set production environment
ENV BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    RAILS_SERVE_STATIC_FILES="true" \
    RAILS_ENV=${RAILS_ENV} \
    RAILS_MASTER_KEY=${RAILS_MASTER_KEY} \
    DATABASE_URL=${DATABASE_URL} \
    CACHE_DATABASE_URL=${CACHE_DATABASE_URL} \
    QUEUE_DATABASE_URL=${QUEUE_DATABASE_URL} \
    BUNDLER_VERSION=${BUNDLER_VERSION}

# Throw-away build stage to reduce size of final image
FROM base as build
ARG BUNDLER_VERSION=2.7.1

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential libpq-dev git libvips pkg-config libyaml-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install application gems
COPY Gemfile Gemfile.lock .ruby-version ./

RUN gem update --system \
    && gem install bundler -v $BUNDLER_VERSION \
    && bundle install -j 4

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 RAILS_ENV=${RAILS_ENV:-production} DATABASE_URL=postgresql://dummy:dummy@localhost/dummy CACHE_DATABASE_URL=postgresql://dummy:dummy@localhost/dummy_cache QUEUE_DATABASE_URL=postgresql://dummy:dummy@localhost/dummy_queue ./bin/rails assets:precompile

# Final stage for app image
FROM base
ARG BUNDLER_VERSION=2.7.1

# Install packages needed for deployment
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl default-mysql-client libvips libpq5 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Copy built artifacts: gems, application
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user for security
RUN useradd rails --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER rails:rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 3000
CMD ["./bin/rails", "server"]
