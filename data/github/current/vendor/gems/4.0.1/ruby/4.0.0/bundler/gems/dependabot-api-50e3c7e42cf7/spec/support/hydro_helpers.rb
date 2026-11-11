# frozen_string_literal: true

module HydroTestHelpers
  def hydro_fixture(schema:, name:)
    fixture_raw = fixture(File.join("hydro_messages", schema, "#{name}.json"))
    fixture_hash = JSON.parse(fixture_raw)

    # Validate the fixture by cycling it through Hydro's
    # validation, encoding and decoding
    encoded_fixture = encode_hydro_message(fixture_hash, schema: schema)
    decode_hydro_message(encoded_fixture)
  end

  def encode_hydro_message(data, schema:)
    encoder = Hydro::ProtobufEncoder.new(Hydro::Site.new("localhost"),
                                         nil_scalar_handler: :ignore)
    hydro_publisher.encode(data, schema: schema, encoder: encoder)
  end

  def decode_hydro_message(bytes)
    Hydro::Decoding::ProtobufDecoder.decode(bytes).message
  end

  def hydro_publisher
    @hydro_publisher ||= Dependabot.hydro_publisher
  end
end
