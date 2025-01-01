# typed: true
# frozen_string_literal: true

module Porter
  module Urls
    extend self

    def porter_url(repository:)
      _expand_porter_repository_template(
        template:   GitHub.porter_url_template,
        repository: repository,
      )
    end

    def porter_api_base_url(repository:)
      porter_url(repository: repository)
    end

    def porter_admin_repository_url(repository:, options: {})
      _expand_porter_repository_template(
        template:   GitHub.porter_repository_admin_url_template,
        repository: repository,
        options:    options,
      )
    end

    def porter_admin_user_url(user:, options: {})
      _expand_porter_user_template(
        template: GitHub.porter_user_admin_url_template,
        user:     user,
        options:  options,
      )
    end

    private

    def _expand_porter_template(template:, options: {})
      template_options = _normalize_porter_template_options(options)

      _expand_porter_url_template(
        template:         template,
        template_options: template_options,
      )
    end

    def _expand_porter_user_template(template:, user:, options: {})
      template_options = _normalize_porter_template_options(
        options,
      ).reverse_merge(
        "login"     => user.login,
        "id"        => user.id,
      )

      _expand_porter_url_template(
        template:         template,
        template_options: template_options,
      )
    end

    def _expand_porter_repository_template(template:, repository:, options: {})
      template_options = _normalize_porter_template_options(
        options,
      ).reverse_merge(
        "owner"      => repository.owner.to_s,
        "repository" => repository.to_s,
        "id"         => repository.id,
      )

      _expand_porter_url_template(
        template:         template,
        template_options: template_options,
      )
    end

    def _normalize_porter_template_options(options)
      template_options = {}
      if options[:json]
        template_options["format"] = "json"
      end
      template_options
    end

    def _expand_porter_url_template(template:, template_options:)
      Addressable::Template.new(template).expand(template_options).to_str
    end
  end
end
