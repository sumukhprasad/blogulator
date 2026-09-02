require "sinatra"
require "time"

set :bind, "0.0.0.0"
set :port, 4567

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
	else
		puts body
	end

	puts

	request.body.rewind
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
				<atom:title>Blogulator! Demo</atom:title>

				<collection href="http://localhost:4567/atompub/posts">
					<atom:title>Posts</atom:title>
					<accept>application/atom+xml;type=entry</accept>
				</collection>
			</workspace>
		</service>
	XML
end

# redirect services that might use this instead
get "/service" do
	redirect "/atompub/service"
end


# catch-all logger
before do
end

%w[get post put patch delete options head].each do |method|
	send(method, "/*") do
		dump_request

		content_type "text/plain"

		"ok\n"
	end
end