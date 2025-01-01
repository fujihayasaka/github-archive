# typed: true
# frozen_string_literal: true

require "github/ds_extensions"

# `KeyValueBase` is the base class for a model designed to be stored in KV,
# as a JSON representation of the model.
#
# Usage:
#   class KVUserModel < KeyValueBase
#     self.prefix_key = "kv_models/user"
#     self.expires_in 10.days
#     attribute :name
#     attribute :enterprise, type: :boolean, default: false
#     primary_index :org, :login
#   end
#
# In the example above, a user model will be stored in KV. And the attributes name, org and login
# will be present.
# The index to look-up this model will be org and login. Defined by calling the `primary_index` method.
# And the prefix key will be "kv_models/user". For example, a value would be stored at the key `kv_models/user/1/arthurnn`
# where 1 is the org and `arthurnn` is the login.
#
# Read methods:
#  `find`:  Finds a model by its primary index. It returns the model itself, or nil if not found.
#           i.e.: `KVUserModel.find(org: 1, login: "foo")`
#           Note that to use the `find` method, all the primary index must be included in the arguments.
#             the other arguments will be ignored.
#
#  `find_all`:  Finds a list of models by its primary index. It returns a Enumerable class.
#               i.e.: `KVUserModel.find_all(org: 1)`
#               Note that to use the `find_all` method, the leading part of the primary index needs to be included.
# ``
# Write methods:
#  `save!`:  Saves the model. It returns the model itself.
class KeyValueBase
  include ActiveModel::Model
  include ActiveModel::Validations
  include ActiveModel::Attributes


  class_attribute :prefix_key

  def self.primary_index(*keys)
    @primary_index = keys.map(&:to_s)

    @primary_index.each do |key|
      self.attribute(key, type: :string)
      self.validates(key, presence: true)
    end
  end

  def self.primary_index_keys
    @primary_index
  end

  def self._store
    GitHub.kv # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  def self.expires_in(duration)
    @expires_in = duration
  end

  def self.expiration_date
    @expires_in && @expires_in.from_now
  end

  def self.find_all(attrs)
    attrs.keys.each_with_index do |k, i|
      k = k.to_s
      raise ArgumentError, "unknown primary index: #{k}, expected #{primary_index_keys[i]}" if primary_index_keys[i] != k
    end

    Collection.new(self, attrs)
  end

  def self.find(attrs)
    raise ArgumentError, "primary index need to be present. Given: #{attrs.keys}" if attrs.keys.map(&:to_s) != primary_index_keys

    key_parts = [prefix_key] + attrs.values
    v = _store.get(key_parts.join("/")).value!
    return nil if v.nil?
    self.new.load_json(v).persisted!
  end

  def self.create!(attrs)
    self.new(attrs).save!
  end

  def persisted!
    @persisted = true
    self
  end

  def persisted?
    !!@persisted
  end

  def load_json(json_data)
    JSON.load(json_data)&.each do |k, v|
      begin
        _write_attribute(k, v)
      rescue ActiveModel::MissingAttributeError
        # `KeyValueBase` is intended for use in quickly developing new features,
        # so we are forgiving of unknown attributes found in the stored JSON
      end
    end
    self
  end

  def to_json
    attributes.to_json
  end

  def save!
    validate!

    self.class._store.set(full_key, to_json, expires: self.class.expiration_date)
    persisted!
  end

  def delete!
    self.class._store.del(full_key)
    nil
  end

  def full_key
    key = [self.prefix_key]
    self.class.primary_index_keys.each do |k|
      key << attribute(k)
    end
    key.join("/")
  end

  class Collection
    include Enumerable

    def initialize(model, key_attrs)
      @model = model
      @key_attrs = key_attrs
      @key_parts = [model.prefix_key] + key_attrs.values
      query_parts = @key_parts.join("/")
      # If trying to find entries by PARTS of the primary index, we need to
      # append a / at the end of the key parts, to avoid collisions when searching
      # i.e.: "kv_models/prefix/1/" will match "kv_models/prefix/1/foo" and not "kv_models/prefix/11/foo"
      if key_attrs.keys.size < model.primary_index_keys.size
        query_parts << "/"
      end
      @kvs = model._store.mget_prefix(query_parts).value!
    end

    def find_or_build_by(attrs)
      key_parts = @key_parts + attrs.values

      full_attrs = attrs.merge(@key_attrs)
      k = key_parts.join("/")
      v = @kvs[k]
      model =
        if v
          @model.new(full_attrs).persisted!
        else
          @model.new(full_attrs)
        end

      model.load_json(v)
      yield(model) if block_given?
      model
    end

    def each(&block)
      @kvs.each do |_k, v|
        yield @model.new.load_json(v).persisted!
      end
    end
  end
end
