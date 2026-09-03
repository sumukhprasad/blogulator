require 'nokogiri'


class Post
	attr_accessor :id, :title, :body, :slug, :date, :created_at, :updated_at, :path, :metadata

	def initialize(
		id: nil,
		title: "",
		body: "",
		slug: nil,
		date: nil,
		created_at: nil,
		updated_at: nil,
		path: nil,
		metadata: {}
	)
		@id = id
		@title = title
		@body = body
		@slug = slug
		@date = date
		@created_at = created_at
		@updated_at = updated_at
		@path = path
		@metadata = metadata
	end

	def persisted?
		!@id.nil?
	end

	def new_record?
		!persisted?
	end

	def filepath
		return nil unless date

		"#{date.strftime("%Y/%m/%d")}/"
	end
	
	
	# TODO: add metadata support, add updated_at key
	def to_file
		<<~MD
			---
			title: "#{title}"
			date: #{date.iso8601}
			---
						
			#{body}
		MD
	end
end
