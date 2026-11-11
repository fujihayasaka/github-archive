# frozen_string_literal: true

if Dependabot.enterprise?
  prefix = "dependabot_"

  Rails.application.reloader.to_prepare do
    {
      Account => %w(account_transitions),
      PullRequest => %w(repos update_configs updated_dependencies autofix_suggestion_jobs),
      UpdateJob => %w(update_configs),
      UpdateJobError => %w(update_configs update_jobs repos),
    }.each do |type, attributes|
      attributes.each do |attribute|
        type.attribute_aliases[attribute] = "#{prefix}#{attribute.pluralize}"
      end
    end
  end

  ActiveSupport.on_load(:active_record) do |clazz|
    clazz.table_name_prefix = prefix
  end
  ActiveSupport.on_load(:active_storage_attachment) do |clazz|
    clazz.table_name = "dependabot_active_storage_attachments"
  end
  ActiveSupport.on_load(:active_storage_blob) do |clazz|
    clazz.table_name = "dependabot_active_storage_blobs"
  end
  ActiveSupport.on_load(:active_storage_variant_record) do |clazz|
    clazz.table_name = "dependabot_active_storage_variant_records"
  end

  Rails.configuration.active_record.table_name_prefix = prefix
end
