# typed: true
# frozen_string_literal: true

module Newsies
  # Horcrux shim around NotificationUserSetting.  Content is returned as a
  # Newsies::Settings (or suitable subclass).
  #
  # This Settings Store is a Horcrux shim around an ActiveRecord model.
  # The model is serialized to and from the attributes Hash of the model.
  class ActiveRecordSettingsStore
    include Horcrux::Methods

    # client     - ActiveRecord class to load data from.
    # serializer - Module to serialize data.
    # settings   - A Class of the instance of the returned settings.  Should
    #              be a subclass of Newsies::Settings.
    def initialize(client, serializer, settings)
      @client = client
      @serializer = serializer
      @settings = settings
    end

    # Public: Checks to see if the Settings for the given ID exist.
    #
    # id - The User or Integer ID of the User.
    #
    # Returns a Boolean.
    def key?(id)
      client.exists?(to_settings_id(id))
    end

    # Public: Gets the Settings for a User.
    #
    # id - The User or Integer ID of the User.
    #
    # Returns a Newsies::Settings or nil.
    def get(id)
      get_all(id).first
    end

    # Public: Get the Settings for a batch of Users.
    #
    # *ids - One or more User or Integer IDs of Users.
    #
    # Returns an Array of Newsies::Settings or nil, in the order the IDs were
    # passed in the argument.
    def get_all(*ids)
      records = query_records(ids)
      ids.map do |id|
        id = to_settings_id(id)
        if record = records[id]
          @serializer.load(record).identify(id)
        else
          @settings.new
        end
      end
    end

    # Public: Saves Settings for a User.
    #
    # id   - The User or Integer ID of the User.
    # hash - The Hash of Settings to save.
    #
    # Returns nothing.
    def set(id, hash)
      set_all(id => hash).first.present?
    end

    # Public: Saves Settings for a Batch of Users.
    #
    # values - A Hash of User or Integer ID keys and Hash Settings values.
    #
    # Returns nothing.
    def set_all(values)
      good_ids = []
      values.each do |user, settings|
        @client.set_for_user(user, settings)
        good_ids << to_settings_id(user)
      end
      good_ids
    end

    # Public: Deletes the Settings for a User.
    #
    # id - The User or Integer ID of the User.
    #
    # Returns nothing.
    def delete(id)
      delete_all(id)
    end

    # Public: Deletes the Settings for a batch of Users.
    #
    # *ids - One or more User or Integer IDs of Users.
    #
    # Returns nothing.
    def delete_all(*ids)
      client.where(id: ids.map { |id| to_settings_id(id) }).delete_all
    end

    # Queries the Settings for a batch of Users.
    #
    # ids - An Array of Integer User IDs.
    #
    # Returns a Hash of Integer User ID keys and Settings values.
    def query_records(ids)
      client.where(id: ids).index_by { |m| m.id }
    end

    # Normalizes a User into an Integer User ID for querying.
    #
    # id - A User or Integer ID.
    #
    # Returns an Integer User ID.
    def to_settings_id(id)
      id.is_a?(ActiveRecord::Base) ? id.id : id.to_i
    end
  end
end
