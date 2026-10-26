#!/usr/bin/env bats
# epico-depdiff, slice 1.3: the runtime names of pyproject.toml,
# requirements.txt, Gemfile and composer.json, on real temporary git repositories.

bats_require_minimum_version 1.5.0

setup() { . "$BATS_TEST_DIRNAME/lib/depdiff-fixture.sh"; depdiff_fixture_setup; }

teardown() { rm -rf "$R" ${O:+"$O"} ${N:+"$N"}; }

@test "1.3: pyproject [project] dependencies on one line and on many, names cut and lower-cased" {
  put pyproject.toml <<'EOF'
[project]
name = "app"
dependencies = ["requests>=2.31", "Flask[async] ; python_version >= '3.8'", "attrs"]

[project.optional-dependencies]
dev = ["pytest>=8"]
EOF
  put services/worker/pyproject.toml <<'EOF'
[project]
name = "worker"
description = """
[tool.poetry.dependencies]
not-a-dependency = "1"
"""
dependencies = [
    # the HTTP client
    "httpx (>=0.27)",
    "PyYAML~=6.0",
    'tomli; python_version < "3.11"',
    "django-ninja!=1.0",
    "pkg @ https://example.com/pkg-1.0.tar.gz",
    "zope.interface<7",
]
EOF
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  new_is "pyproject.toml attrs" "pyproject.toml flask" "pyproject.toml requests" \
    "services/worker/pyproject.toml django-ninja" "services/worker/pyproject.toml httpx" \
    "services/worker/pyproject.toml pkg" "services/worker/pyproject.toml pyyaml" \
    "services/worker/pyproject.toml tomli" "services/worker/pyproject.toml zope.interface"
  printf '%s' "$output" | jq -e '.new | all(.ecosystem == "pypi")' > /dev/null
}

@test "1.3: [tool.poetry.dependencies] keys are new except python; dev groups are not" {
  put pyproject.toml <<'EOF'
[tool.poetry]
name = "app"

[tool.poetry.dependencies]
python = "^3.11"
Django = "^5.0"
celery = { version = "^5.3", extras = ["redis"] }
numpy = [
    { version = "^1.24", python = "<3.12" },
    { version = "^2.0", python = ">=3.12" },
]

[tool.poetry.group.dev.dependencies]
pytest = "^8"

[tool.poetry.dev-dependencies]
black = "^24"
EOF
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  new_is "pyproject.toml celery" "pyproject.toml django" "pyproject.toml numpy"
}

@test "1.3: requirements.txt skips blanks, comments, options and URLs; requests then requests-oauthlib is new" {
  put requirements.txt <<'EOF'
requests==2.31.0
EOF
  B=$(snapshot base)
  put requirements.txt <<'EOF'
# pinned for production

requests==2.32.0
requests-oauthlib>=1.3  # OAuth for the API client
-r other.txt
-e git+https://github.com/example/editable.git#egg=editable
--index-url https://pypi.org/simple
https://example.com/archive-1.0.tar.gz
git+https://github.com/example/vcs.git
./local/package
Jinja2[i18n]>=3 ; python_version >= "3.8"
EOF
  snapshot head > /dev/null
  depdiff_run --base "$B"
  [ "$status" -eq 0 ]
  new_is "requirements.txt jinja2" "requirements.txt requests-oauthlib"
  printf '%s' "$output" | jq -e '.new | all(.ecosystem == "pypi")' > /dev/null
}

@test "1.3: a case-only rename of a Python name is not new" {
  put requirements.txt <<'EOF'
PyYAML==6.0
EOF
  put pyproject.toml <<'EOF'
[project]
dependencies = ["Requests>=2"]
EOF
  B=$(snapshot base)
  put requirements.txt <<'EOF'
pyyaml==6.0.1
EOF
  put pyproject.toml <<'EOF'
[project]
dependencies = ["requests>=2"]
EOF
  snapshot head > /dev/null
  depdiff_run --base "$B"
  [ "$status" -eq 0 ]
  new_is
}

@test "1.3: Gemfile top-level gems are new; :development and :test groups, block or inline, are not" {
  put Gemfile <<'EOF'
source "https://rubygems.org"
gem "rails"
EOF
  B=$(snapshot base)
  put Gemfile <<'EOF'
source "https://rubygems.org"
ruby "3.3.0"

gem "rails", "~> 7.1"
gem 'pg'
gem "sidekiq", require: false

group :development do
  gem "pry"
end

group :test do
  gem "rspec"
end

group :development, :test do
  gem "rubocop"
end

gem "capybara", group: :test
gem "byebug", groups: [:development, :test]
gem "web-console", :group => :development

group :production do
  gem "lograge"
end

platforms :jruby do
  gem "activerecord-jdbc-adapter"
end
EOF
  snapshot head > /dev/null
  depdiff_run --base "$B"
  [ "$status" -eq 0 ]
  new_is "Gemfile activerecord-jdbc-adapter" "Gemfile lograge" "Gemfile pg" "Gemfile sidekiq"
  printf '%s' "$output" | jq -e '.new | all(.ecosystem == "rubygems")' > /dev/null
}

@test "1.3: composer require is new except php, ext-* and other platform names; require-dev is not" {
  put composer.json <<'EOF'
{"require": {"php": ">=8.1"}}
EOF
  B=$(snapshot base)
  put composer.json <<'EOF'
{"require": {"php": ">=8.2", "ext-json": "*", "lib-icu": "*", "composer-plugin-api": "^2",
             "monolog/monolog": "^3", "php-http/httplug": "^2"},
 "require-dev": {"phpunit/phpunit": "^10"}}
EOF
  snapshot head > /dev/null
  depdiff_run --base "$B"
  [ "$status" -eq 0 ]
  new_is "composer.json monolog/monolog" "composer.json php-http/httplug"
  printf '%s' "$output" | jq -e '.new | all(.ecosystem == "composer")' > /dev/null
}

@test "1.3: an unclosed pyproject array, a Gemfile gem with no literal name and broken composer JSON go to unparsed" {
  put pyproject.toml <<'EOF'
[project]
dependencies = [
    "requests",
EOF
  put Gemfile <<'EOF'
gem "rack"
gem ENV.fetch("ADAPTER")
EOF
  put composer.json <<'EOF'
{"require": {"monolog/monolog": "^3"
EOF
  put requirements.txt <<'EOF'
requests
!!! not a requirement
EOF
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  one_object
  new_is
  [ "$(unparsed_manifests)" = "$(printf 'Gemfile\ncomposer.json\npyproject.toml\nrequirements.txt')" ] \
    || { echo "unparsed: $(unparsed_manifests)"; return 1; }
  # The reason quotes the line that broke the parse.
  printf '%s' "$output" | jq -e '
    [.unparsed[].reason] | any(contains("dependencies = ["))
    and any(contains("ENV.fetch"))
    and any(contains("!!! not a requirement"))' > /dev/null
}

@test "1.3: an unbalanced end in a Gemfile goes to unparsed" {
  put Gemfile <<'EOF'
group :test do
  gem "rspec"
end
end
gem "rack"
EOF
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  new_is
  [ "$(unparsed_manifests)" = "Gemfile" ]
}
