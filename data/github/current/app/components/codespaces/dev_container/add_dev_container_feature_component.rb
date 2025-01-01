# typed: true
# frozen_string_literal: true

class Codespaces::DevContainer::AddDevContainerFeatureComponent < ApplicationComponent
  def initialize(feature:)
    @feature = feature
    @copyable_example = generate_copyable_example
  end

  def generate_copyable_example
    feature_id_with_major_version = @feature["id"]
    if !@feature["majorVersion"].blank?
      feature_id_with_major_version = "#{@feature["id"]}:#{@feature["majorVersion"]}"
    end

    "\"#{feature_id_with_major_version}\": {}"
  end

end
