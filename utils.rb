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
	
	
	def self.sanitize_filename(filename)
	  	filename.strip.tap do |name|
	  		name.gsub!(/^.*(\\|\/)/, '')
       	 	
	  		name.gsub!(/[^0-9A-Za-z.\-]/, '_')
	  	end
	end
	
	
	def self.get_unique_filename(directory, filename)
		extension = File.extname(filename)
		basename = File.basename(filename, extension)
         	
		filename_new = filename
		counter = 2
         	
		while File.exist?(directory.join(filename_new))
			filename_new = "#{basename}-#{counter}#{extension}"
			counter += 1
		end
         	
		filename_new
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