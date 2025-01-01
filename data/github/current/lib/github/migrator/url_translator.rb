# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class UrlTranslator
      def initialize(from: nil, to: DefaultUrlTemplates)
        @from = from || {}
        @to   = to
      end

      attr_accessor :from, :to

      # Takes a source_url and generates a guess at the target_url.
      #
      # This is similar to what model_url_service does, but we don't have any models available.
      def translate(model_type, source_url)
        source_template = from[model_type] || DefaultUrlTemplates[model_type]
        target_template = to[model_type]

        return nil if source_template.nil? || target_template.nil?

        params = T.let(nil, T.untyped)
        if source_template.is_a?(Hash)
          source_template.each do |subtype, template|
            if params = extract(template, source_url)
              target_template = target_template[subtype]
              break
            end
          end
        else
          params = extract(source_template, source_url)
        end

        if params.nil?
          path = sanitized_path(source_url).inspect
          raise(UnrecognizableUrlError, "Couldn't recognize #{path} as a #{model_type}!")
        end

        expand(target_template, params.merge(default_params))
      end

      def default_params
        {
          "scheme" => GitHub.scheme,
          "host" => GitHub.host_name,
        }
      end

      def extract(template, url)
        template = Addressable::Template.new(template)
        template.extract(Addressable::URI.parse(url))
      end

      def expand(template, params)
        template = Addressable::Template.new(template)
        template.expand(params).to_s
      end

      private

      def sanitized_path(url)
        Addressable::URI.parse(url).path
      end
    end
  end
end
