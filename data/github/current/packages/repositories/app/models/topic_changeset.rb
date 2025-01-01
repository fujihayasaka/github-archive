# typed: true
# frozen_string_literal: true

class TopicChangeset
  attr_reader :topic, :new_related, :new_aliases

  def initialize(topic)
    @topic = topic
    @is_new = topic.new_record?
    @old_aliases = topic.alias_names
    @old_related = topic.related_topic_names
  end

  # Public: Returns true if the Topic is a new record not yet saved to the database.
  def new?
    @is_new
  end

  # Public: Returns true if the Topic exists in the database but has changes that aren't saved.
  def changed?
    !new? && @changes.present?
  end

  # Public: Call this after fields have been updated on the Topic but before #save is called. It
  # will determine which values have changed, including topic relations.
  #
  # metadata - a hash of topic metadata pulled from a Markdown file in github/explore
  #
  # Returns nothing.
  def determine_changes(metadata = {})
    @new_aliases = topic_alias_names_from(metadata)
    @new_related = related_topic_names_from(metadata)

    @changes = @topic.changed_attributes.dup
    @changes = @changes.reject do |field, old_value|
      new_value = topic.send(field)
      if new_value.is_a?(String) && old_value.is_a?(String) && old_value != new_value
        old_value.force_encoding("UTF-8") == new_value.force_encoding("UTF-8")
      else
        false
      end
    end
    @changes = @changes.to_h

    unless @old_aliases.sort == @new_aliases.sort
      @changes["aliases"] = {
        "old" => @old_aliases.join(", "),
        "new" => @new_aliases.join(", "),
      }
    end
    unless @old_related.sort == @new_related.sort
      @changes["related"] = {
        "old" => @old_related.join(", "),
        "new" => @new_related.join(", "),
      }
    end
  end

  # Public: Iterates over each changed field, giving the field and the old value.
  def each
    sorted_changes.each_pair do |field, value|
      yield field, value
    end
  end

  # Public: Returns a hash of the Topic's changed fields and their old values.
  def to_h
    sorted_changes.dup
  end

  private

  def sorted_changes
    @sorted_changes ||= @changes.sort_by { |field, _value| field }.to_h
  end

  def related_topic_names_from(metadata)
    related_str = metadata["related"] || ""
    Topic.normalize_and_extract_valid_names(related_str.split(Topic::ALIAS_DELIMITER))
  end

  def topic_alias_names_from(metadata)
    aliases_str = metadata["aliases"] || ""
    Topic.normalize_and_extract_valid_names(aliases_str.split(Topic::ALIAS_DELIMITER))
  end
end
