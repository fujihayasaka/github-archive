require 'zlib'

def decrypt(s)
    i, plaintext = 0, ''
    key = "This obfuscation is intended to discourage GitHub Enterprise customers from making modifications to the VM. We know this 'encryption' is easily broken. "

    Zlib::Inflate.inflate(s).each_byte do |c|
        plaintext << (c ^ key[i%key.length].ord).chr
        i += 1
    end
    plaintext
end

Dir.glob("data/**/*.rb").each do |file|
  content = File.read(file)

  next if !content.include? "__ruby_concealer__"

  content.sub! %Q(__ruby_concealer__), " decrypt "
  plaintext = eval content

  File.open(file, "w") do |f|
    f.write plaintext
  end
end
