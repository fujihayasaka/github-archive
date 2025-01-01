# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  # This module serves as the interface between field-specific processor implementations within the Indexable domain
  # on the one side, and the StreamProcessors domain on the other.
  #
  # Any class that has inherited from the Indexable::Processor::Base class may register itself here in order to be
  # picked up by the projects denormalization stream processor, though the primary codepath is for a subclass of
  # MemexProjectColumn::Field::Base to call `register_processors` with the Indexable::Processor::Base subclasses it needs
  # to denormalize its data into Elasticsearch.
  module Processor
    include Kernel

    IndexableProcessor  = T.type_alias { T.class_of(Base) }
    Topics              = T.type_alias { T::Array[Regexp] }

    # Processors that are not associated with particular fields can be declared here. Field-specific processors
    # will be fetched below.
    PROCESSOR_REGISTRY = T.let(
      [
        "MemexProjectColumn::Interface::Indexable::Processor::BulkArchiveProjectItems",
        "MemexProjectColumn::Interface::Indexable::Processor::ColumnDestroy",
        "MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange",
        "MemexProjectColumn::Interface::Indexable::Processor::IssueTransferUpdates",
        "MemexProjectColumn::Interface::Indexable::Processor::ProcessProjectDestroy",
        "MemexProjectColumn::Interface::Indexable::Processor::ProjectItemMetadataUpdate",
        "MemexProjectColumn::Interface::Indexable::Processor::ProjectItemMove",
        "MemexProjectColumn::Interface::Indexable::Processor::ProcessProjectItem",
        "MemexProjectColumn::Interface::Indexable::Processor::ProcessProjectItemDelete",
        "MemexProjectColumn::Interface::Indexable::Processor::ProjectRebalanced",
      ],
      T::Array[String]
    )

    sig { returns(T::Array[IndexableProcessor]) }
    def self.registered_processors
      Set.new(
        PROCESSOR_REGISTRY +
        field_processors
      )
      .map(&:constantize)
    end

    # Extract processor class names that have been declared by fields
    sig { returns(T::Array[String]) }
    private_class_method def self.field_processors
      MemexProjectColumn::FieldDependency::FIELD_CLASS_REGISTRY.each_with_object([]) do |class_string, result|
        klass = class_string.constantize
        result.concat(klass.register_processors) unless klass.exclude_from_index?
      end
    end

    # Collect and expose all the registered topics so that the stream processor can subscribe to them.
    sig { returns(Topics) }
    def self.registered_topics
      registered_processors
        .map(&:topics)
        .flatten
        .uniq
    end

    # Expose a hook for the stream processor to call, passing in the message and getting back 1 or more processors
    # that have registered with the topic of the message.
    #
    # Note that we return an array of matching processors for now to allow for the possibility that more than one processor
    # may want to subscribe to the same topic. We don't expect this to happen often, but this is a friendlier interface
    # for this level of architectural maturity than having last-in clobber the rest.
    sig do
      params(
        message: GitHub::StreamProcessors::Message
      ).returns(
        T::Array[Base]
      )
    end
    def self.for_message(message)
      processors = registered_processors
        .filter_map do |processor|
          processor.new(message) if processor.topics.any? { |topic| message.topic.match(topic) }
        end

      if processors.empty?
        raise NotImplementedError, "No processor for #{message.topic} has been registered"
      end

      processors
    end

  end
end
