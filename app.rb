require "sinatra"
require "sinatra/reloader"
require "http"
require "json"
require "openai"
require "sinatra/cookies"
require "kramdown"

gmaps_key = ENV.fetch("GMAPS_KEY")
pirate_weather_key = ENV.fetch("PIRATE_WEATHER_KEY")

future_key = ENV.fetch("FUTURE_KEY")

OpenAI.configure do |config|
  config.access_token = future_key
end

client = OpenAI::Client.new

delete_cookies = false


get("/") do
  erb(:homepage)
end

get("/umbrella") do
  erb(:umbrella)
end

get("/process_umbrella") do
  @user_location = params.fetch("user_loc")
  
  user_location_no_space = @user_location.gsub(" ", "+")

  gmaps_url = "https://maps.googleapis.com/maps/api/geocode/json?address=#{user_location_no_space}&key=#{gmaps_key}"

  @raw_gmaps_data = HTTP.get(gmaps_url).to_s
  @parsed_gmaps_data = JSON.parse(@raw_gmaps_data)
  @loc_hash = @parsed_gmaps_data.dig("results", 0, "geometry", "location")

  @latitude = @loc_hash.fetch("lat")
  @longitude = @loc_hash.fetch("lng")

  @pirate_weather_data = HTTP.get("https://api.pirateweather.net/forecast/#{pirate_weather_key}/#{@latitude},#{@longitude}")
  @parsed_pirate_data = JSON.parse(@pirate_weather_data)
  @currently = @parsed_pirate_data.fetch("currently")
  @temperature = @currently.fetch("temperature")

  minutely_hash = @parsed_pirate_data.fetch("minutely", false)

  if minutely_hash
    @summary_hash = minutely_hash.fetch("summary")
  end

  hourly = @parsed_pirate_data.fetch("hourly")
  data_ = hourly.fetch("data")
  next_twelve_hours = data_[1..12]

  threshold = 0.1
  take_umbrella = false

  next_twelve_hours.each do |rain|
    rain_prob = rain.fetch("precipProbability")
    if rain_prob >= threshold
      take_umbrella = true
    end
  end

  if take_umbrella == false
    @answer = "You probably won’t need an umbrella today."
  else 
    @answer = "You might want to take an umbrella!"  
  end

  erb(:umbrella_results)
end

get("/message") do
  erb(:message)
end

post("/process_message") do
  @process_message = params.fetch("process_message")

  response = client.chat(
    parameters: {
        model: "gpt-3.5-turbo",
        messages: [{ role: "user", content: @process_message}, { role: "assistant", content: "Write as a haiku"}],
        temperature: 0.7,
    })

  choices = response.fetch("choices")
  choice = choices[0]
  message = choice.fetch("message")
  @chat_gpt = message.fetch("content")

  erb(:message_results)
end

get("/chat") do
  if delete_cookies == false
    @test = cookies["chat_history"]
    @test_parse = JSON.parse(@test)
  else 
    @test_parse = []
    delete_cookies = false
  end

  erb(:chat)
end

post("/process_chat") do
  user_message = params.fetch("user_message")

  old_chat_history_string = cookies["chat_history"]

  if old_chat_history_string == nil
    chat_history_array = []
  else
    chat_history_array = JSON.parse(old_chat_history_string)
  end

  chat_history_array.push(
    { :role => "user", :content => user_message }
  )

  response = client.chat(
    parameters: {
        model: "gpt-3.5-turbo",
        messages: chat_history_array,
        temperature: 0.7,
    })

  choices = response.fetch("choices")
  choice = choices[0]
  message = choice.fetch("message")
  chat_gpt = message.fetch("content")

  chat_history_array.push(
    { :role => "assistant", :content => chat_gpt }
  )

  new_chat_history_string = JSON.generate(chat_history_array)

  cookies["chat_history"] = new_chat_history_string

  redirect("/chat")

end

post("/delete_chat") do
  cookies.clear
  delete_cookies = true

  redirect("/chat")

end
