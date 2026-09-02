require "stringex"

module Utils
	def self.slugify(s)
		s.to_url
	end
	
	def self.unique_slug(directory, slug)
		slug = "#{slug}"
		slug_new = "#{slug}"
		counter = 2

		while File.exist?(directory.join(slug_new+".md"))
			slug_new = "#{slug}-#{counter}"
			counter += 1
		end

		slug_new
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