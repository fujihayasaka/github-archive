# typed: true
# frozen_string_literal: true

class Repos::Security::DeleteConfigurationDialogComponent < ApplicationComponent
  include ReactHelper
  with_collection_parameter :branch

  def initialize(branch:, branch_counter:, form_submit_path:, read_only_user:, default_branch:)
    @branch = branch
    @counter = branch_counter
    @form_submit_path = form_submit_path
    @read_only_user = read_only_user
    @default_branch = default_branch
  end

  attr_reader :branch
  attr_reader :counter
  attr_reader :form_submit_path
  attr_reader :read_only_user
  attr_reader :default_branch

  def stale_alerts_dialog_id
    "stale-alerts-dialog-id-#{counter}"
  end

  def all_fixed?
    branch[:instances].all? { |i| i[:is_fixed] }
  end

  def icon
    return "shield-x" if branch[:dismissed?]
    all_fixed? ? "shield-check" : "shield"
  end

  def color
    return :closed if branch[:dismissed?]
    all_fixed? ? :done : :success
  end

  def csrf
    authenticity_token_for @form_submit_path, method: :post
  end

  def instances
    branch[:instances].each do |instance|
      next if instance[:created_at].nil?
      instance[:created_at] = instance[:created_at].to_time.iso8601
    end
    branch[:instances]
  end

  def show_default_branch_empty_state_dialog?
    branch[:name] == default_branch && branch[:instances].empty?
  end

  def stale_alerts_docs_link
    DocsUrlConfig.url_for("code-security/removing-stale-configurations")
  end

  def safe_branch_name
    branch[:name].dup.force_encoding(Encoding::UTF_8).scrub!
  end
end
