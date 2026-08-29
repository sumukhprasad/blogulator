require "stringex"

module Utils
	def self.slugify(s)
		s.to_url
	end
end



if __FILE__ == $0
	puts "Blogulator Utils Test"
	puts "====================="
	puts ""
	
	puts "Utils.slugify, `$12 worth of Ruby power`"
	puts Utils.slugify("$12 worth of Ruby power")
	puts ""
end