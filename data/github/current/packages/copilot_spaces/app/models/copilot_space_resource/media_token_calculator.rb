# typed: true
# frozen_string_literal: true

# This follows the logic in https://platform.openai.com/docs/guides/images-vision?api-mode=chat#calculating-costs
class CopilotSpaceResource::MediaTokenCalculator
  # Constants based on GPT-4 vision token calculation methodology
  BASE_TOKENS = 85
  TILE_TOKENS = 170
  MAX_DIMENSION = 2048
  TARGET_DIMENSION = 768
  TILE_SIZE = 512

  # Calculate the number of tokens required for an image based on its dimensions
  # following OpenAI's GPT-4 vision methodology
  sig { params(width: Integer, height: Integer).returns(Integer) }
  def self.calculate_image_tokens(width, height)
    return 0 if width <= 0 || height <= 0

    # Step 1: Check if resizing is needed (if either dimension exceeds MAX_DIMENSION)
    width, height = resize_image(width, height)

    # Step 2: Scale the image so the shortest side is TARGET_DIMENSION (768px)
    width, height = scale_to_target(width, height)

    # Step 3: Calculate how many TILE_SIZE (512px) tiles are needed
    tiles_wide = (width.to_f / TILE_SIZE).ceil
    tiles_high = (height.to_f / TILE_SIZE).ceil
    total_tiles = tiles_wide * tiles_high

    # Step 4: Calculate total tokens
    BASE_TOKENS + (total_tiles * TILE_TOKENS)
  end


  # Resize image if either dimension exceeds MAX_DIMENSION while maintaining aspect ratio
  sig { params(width: Integer, height: Integer).returns([Integer, Integer]) }
  def self.resize_image(width, height)
    return [width, height] if width <= MAX_DIMENSION && height <= MAX_DIMENSION

    aspect_ratio = width.to_f / height

    if width > height
      # Width is the longer side
      new_width = MAX_DIMENSION
      new_height = (new_width / aspect_ratio).to_i
      [new_width, new_height]
    else
      # Height is the longer side
      new_height = MAX_DIMENSION
      new_width = (new_height * aspect_ratio).to_i
      [new_width, new_height]
    end
  end

  # Scale image so the shortest side is TARGET_DIMENSION
  sig { params(width: Integer, height: Integer).returns([Integer, Integer]) }
  def self.scale_to_target(width, height)
    if width < height
      # Width is shorter
      scale = TARGET_DIMENSION.to_f / width
      new_width = TARGET_DIMENSION
      new_height = (height * scale).to_i
      [new_width, new_height]
    else
      # Height is shorter (or equal)
      scale = TARGET_DIMENSION.to_f / height
      new_height = TARGET_DIMENSION
      new_width = (width * scale).to_i
      [new_width, new_height]
    end
  end
end
