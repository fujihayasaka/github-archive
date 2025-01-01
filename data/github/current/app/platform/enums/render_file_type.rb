# typed: strict
# frozen_string_literal: true
module Platform
  module Enums
    class RenderFileType < Platform::Enums::Base
      description "The detected Render file type."

      visibility :internal

      value "GEOJSON", "A GeoJSON file.", value: :geojson
      value "IMG", "An image file.", value: :img
      value "IPYNB", "A IPython Notebook file.", value: :ipynb
      value "PDF", "A PDF file.", value: :pdf
      value "PSD", "A PSD file.", value: :psd
      value "SOLID", "A `.stl` file.", value: :solid
      value "SVG", "A SVG file.", value: :svg
      value "TOPOJSON", "A TopoJSON file.", value: :topojson
    end
  end
end
