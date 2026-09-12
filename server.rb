require "sinatra"
require "time"
require "bcrypt"
require 'securerandom'
require 'yaml'
require_relative "process_xml"
require_relative "posts"
require_relative "media"
require_relative "storage"
require_relative "utils"


blogulator_config = YAML.load_file($blog_name+'-blogulator.yml')


blogulator_storage = Storage.new(".", blogulator_config["media_path"], blogulator_config["posts_path"])
set :bind, "0.0.0.0"

# logging
def dump_request
	puts
	puts "=" * 80
	puts "#{Time.now.iso8601} #{request.request_method} #{request.path}"
	puts "=" * 80

	puts "--- query params ---"
	p request.params unless request.params.empty?

	puts "--- headers ---"
	request.env
		.select { |key, _| key.start_with?("HTTP_") || key == "CONTENT_TYPE" || key == "CONTENT_LENGTH" }
		.each do |key, value|
			puts "#{key}: #{value}"
		end

	puts "--- body ---"
	body = request.body.read

	if body.empty?
		puts "(empty)"
	elsif request.env["CONTENT_TYPE"].include? "image"
		puts "(image)"
	else
		puts body
	end

	puts

	request.body.rewind
end


def request_filename
	content_disposition = request.env["HTTP_CONTENT_DISPOSITION"]
	
	http_slug = request.env["HTTP_SLUG"]
	return http_slug if http_slug
	
	return nil unless content_disposition

	match = content_disposition.match(
		/filename="([^"]+)"/
	)

	match && match[1]
end

def authenticated?
	blogulator_config = YAML.load_file($blog_name+'-blogulator.yml')
	auth = request.env["HTTP_AUTHORIZATION"]
	return false unless auth

	scheme, encoded = auth.split(" ", 2)
	return false unless scheme&.downcase == "basic" && encoded

	username, password = Base64.strict_decode64(encoded).split(":", 2)

	username == blogulator_config["username"] &&
	BCrypt::Password.new(blogulator_config["password_hash"]) == password
rescue ArgumentError
	false
end

def require_auth!
	return if authenticated?

	headers "WWW-Authenticate" => 'Basic realm="Blogulator"'
	halt 401, "authentication required\n"
end




# service document
get "/atompub/service" do
	puts "\n=== SERVICE REQUEST ==="
	dump_request

	content_type "application/atomsvc+xml"

	<<~XML
		<?xml version="1.0" encoding="utf-8"?>
		<service xmlns="http://www.w3.org/2007/app"
						 xmlns:atom="http://www.w3.org/2005/Atom">
			<workspace>
				<atom:title>#{blogulator_config["blog_title"] || "No title in blogulator.yml."}</atom:title>

				<collection href="#{request.base_url}/atompub/posts">
					<atom:title>Posts</atom:title>
					<accept>application/atom+xml;type=entry</accept>
				</collection>

				<collection href="#{request.base_url}/atompub/media">
					<atom:title>Media</atom:title>
					<accept>*/*</accept>
				</collection>
			</workspace>
		</service>
	XML
end

# redirect services that might use this instead
get "/service" do
	redirect "/atompub/service"
end






# POSTS
# categories
get "/atompub/categories" do
	dump_request

	content_type "application/atomcat+xml"

	<<~XML
		<?xml version="1.0" encoding="utf-8"?>
		<app:categories
			xmlns:app="http://www.w3.org/2007/app"
			xmlns:atom="http://www.w3.org/2005/Atom">
			<atom:category term="post" label="Post"/>
		</app:categories>
	XML
end




# collection/feed
get "/atompub/posts" do
	dump_request

	posts = blogulator_storage.get_posts

	content_type "application/atom+xml"

	builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
		xml.feed("xmlns" => "http://www.w3.org/2005/Atom") do
			xml.title "#{blogulator_config["blog_title"] || "No title in blogulator.yml."}"
			xml.id "#{request.base_url}/atompub/posts"

			xml.updated(
				posts.first&.updated_at&.utc&.iso8601 ||
				Time.now.utc.iso8601
			)

			posts.each do |post|
				xml.entry do
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

					xml.content(post.body, "type" => "html")

					xml.link(
						"rel" => "edit",
						"href" => "#{request.base_url}/atompub/posts/#{post.id}"
					)
				end
			end
		end
	end

	builder.to_xml
end


# create an entry
post "/atompub/posts" do
	dump_request

	post = post_from_atom(request.body.read)

	post.slug = Utils.slugify(post.title)
	post.id = SecureRandom.uuid

	post = blogulator_storage.create_post(post)

	content_type "application/atom+xml;type=entry"
	headers "Location" => "#{request.base_url}/atompub/posts/#{post.id}"
	status 201

	post_to_atom(post, request)
end


# individual entry
get "/atompub/posts/:id" do
	dump_request

	post = blogulator_storage.get_post(params[:id])

	halt 404 unless post

	content_type "application/atom+xml"

	post_to_atom(post, request)
end


# update an entry
put "/atompub/posts/:id" do
	dump_request

	post = post_from_atom(request.body.read)
	post = blogulator_storage.update_post(params[:id], post)
	halt 404 unless post

	content_type "application/atom+xml;type=entry"
	post_to_atom(post, request)
end


# delete an entry
delete "/atompub/posts/:id" do
	dump_request

	post = blogulator_storage.get_post(params[:id])
	halt 404 unless post

	blogulator_storage.delete_post(params[:id])

	status 204
end









# Media

# create an entry
post "/atompub/media" do
	no_print_content = true
	dump_request

	filename = request_filename || "upload"
	content_type = request.media_type || "application/octet-stream"
	data = request.body.read

	media = blogulator_storage.create_media(
		filename: filename,
		content_type: content_type,
		data: data
	)

	headers(
		"Location" => "#{request.base_url}/atompub/media/#{media.id}"
	)

	content_type "application/atom+xml;type=entry"
	status 201

	media_to_atom(media, request)
end

get "/atompub/media/:id" do
	dump_request

	media = blogulator_storage.get_media(params[:id])
	halt 404 unless media

	content_type media.content_type
	headers(
		"Content-Length" => media.size.to_s,
		"Last-Modified" => media.updated_at.httpdate
	)

	blogulator_storage.get_media_content(media.id)
end







# catch-all logger
before do
	if %w[POST PUT PATCH DELETE].include?(request.request_method)
		require_auth!
	end
end

%w[get post put patch delete options head].each do |method|
	send(method, "/*") do
		dump_request

		content_type "text/plain"

		"ok\n"
	end
end