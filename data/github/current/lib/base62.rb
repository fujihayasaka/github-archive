# typed: true
# frozen_string_literal: true

# Taken with inspiration from https://rubygems.org/gems/base62/versions/1.0.0
class Base62

  PRIMITIVES = %w[0 1 2 3 4 5 6 7 8 9] + \
  %w[A B C D E F G H I J K L M N O P Q R S T U V W X Y Z] + \
  %w[a b c d e f g h i j k l m n o p q r s t u v w x y z]
  PRIMITIVES_SIZE = 62

  def self.encode(int, min_length: 0)
    return "".rjust(min_length, PRIMITIVES[0]) if int <= 0

    result = T.let("", String)
    while int > 0
      result = PRIMITIVES[int % PRIMITIVES_SIZE] + result
      int /= PRIMITIVES_SIZE
    end

    result.rjust(min_length, PRIMITIVES[0])
  end
end
