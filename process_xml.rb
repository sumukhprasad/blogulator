require "nokogiri"
require "time"

def post_from_atom(xml)
	doc = Nokogiri::XML(xml) do |config|
		config.strict.nonet
	end

	ns = {
		"atom" => "http://www.w3.org/2005/Atom",
		"app"  => "http://www.w3.org/2007/app"
	}

	entry = doc.at_xpath("//atom:entry", ns)
	raise "No <entry> in AtomPub request" unless entry

	title = entry.at_xpath("./atom:title", ns)&.text.to_s
	body = entry.at_xpath("./atom:content", ns)&.text.to_s
	summary = entry.at_xpath("./atom:summary", ns)&.text.to_s

	published = entry.at_xpath("./atom:published", ns)&.text
	date = published ? Time.parse(published) : Time.now

	categories = entry.xpath("./atom:category", ns).filter_map do |category|
		category["term"]
	end

	draft = entry.at_xpath(
		"./app:control/app:draft",
		ns
	)&.text

	Post.new(
		id: nil,
		title: title,
		body: body,
		slug: nil,
		date: date,
		created_at: date,
		updated_at: nil,
		path: nil,
		metadata: {
			summary: summary,
			categories: categories,
			draft: draft
		}
	)
end

def post_to_atom(post, request)
	builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
		xml.entry(
			"xmlns" => "http://www.w3.org/2005/Atom"
		) do
			xml.id "#{request.base_url}/atompub/posts/#{post.id}"
			xml.title post.title

			xml.updated(
				post.updated_at&.utc&.iso8601 ||
				post.created_at&.utc&.iso8601 ||
				Time.now.utc.iso8601
			)

			if post.created_at
				xml.published post.created_at.utc.iso8601
			end

			if post.metadata&.dig(:summary).to_s != ""
				xml.summary post.metadata[:summary]
			end

			post.metadata&.dig(:categories)&.each do |category|
				xml.category "term" => category
			end

			if post.metadata&.key?(:draft)
				xml.control(
					"xmlns" => "http://www.w3.org/2007/app"
				) do
					xml.draft post.metadata[:draft]
				end
			end

			xml.content(
				post.body,
				"type" => "html"
			)

			xml.link(
				"rel" => "edit",
				"href" => "#{request.base_url}/atompub/posts/#{post.id}"
			)
		end
	end

	builder.to_xml
end



def media_to_atom(media, request)
	media_url = "#{request.base_url}/atompub/media/#{media.id}"
	edit_url = media_url
	public_url = "#{request.base_url}/assets/#{media.filename}"

	Nokogiri::XML::Builder.new(
		encoding: "UTF-8"
	) do |xml|

		xml.entry(
			"xmlns" => "http://www.w3.org/2005/Atom"
		) do
			xml.id media_url
			xml.title media.filename
			xml.updated media.updated_at.utc.iso8601

			xml.published media.created_at.utc.iso8601

			xml.link(
				"rel" => "edit",
				"href" => edit_url
			)

			xml.link(
				"rel" => "edit-media",
				"href" => edit_url,
				"type" => media.content_type
			)

			xml.link(
				"rel" => "alternate",
				"href" => public_url
			)

			xml.content(
				"type" => media.content_type,
				"src" => media_url
			)
		end
	end.to_xml
end