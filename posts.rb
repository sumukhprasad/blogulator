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
	
	
	def to_file(blog_options = {})
		front_matter = {
			"title" => @title,
			"date" => @date,
			"slug" => @slug,
			"created_at" => @created_at,
			"updated_at" => @updated_at
		}.compact

		front_matter["author"] = blog_options["author"] if blog_options["author"]
		front_matter["layout"] = blog_options["page_layout"] if blog_options["page_layout"]

		blog_options.each do |key, value|
			front_matter[key.to_s] = value
		end

		metadata.each do |key, value|
			front_matter[key.to_s] = value
		end

		<<~MD
			---
			#{front_matter.to_yaml.sub(/\A---\s*\n/, "").chomp}
			---

			#{body}
		MD
	end
end
