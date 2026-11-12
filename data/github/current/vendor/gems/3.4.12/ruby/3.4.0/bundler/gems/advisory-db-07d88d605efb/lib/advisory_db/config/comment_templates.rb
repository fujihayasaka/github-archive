# frozen_string_literal: true

module AdvisoryDB
  module Config
    module CommentTemplates
      def comment_templates
        @comment_templates ||= YAML.safe_load(Rails.root.join("config/comment_templates.yml").read)
      end
    end

    include CommentTemplates
  end
end
