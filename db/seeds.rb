# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

admin_email = ENV.fetch("ADMIN_EMAIL", "admin@example.com")
admin_password = ENV.fetch("ADMIN_PASSWORD", "changeme123!")

User.find_or_create_by!(email: admin_email) do |u|
  u.password = admin_password
  u.password_confirmation = admin_password
  u.admin = true
end

puts "Admin user: #{admin_email} (password: #{admin_password})"

# Seed example feeds
[
  { name: "CVFolk Calendar",        url: "https://ics.teamup.com/feed/ks587swpgt68os9whe/0.ics",             feed_type: "ical",       fetch_interval_hours: 24 },
  { name: "Earlsdon Library",       url: "https://earlsdonlibrary.org.uk/whats-on/",                         feed_type: "web",        fetch_interval_hours: 48 },
  { name: "LTB Showrooms",          url: "https://www.ltbshowrooms.com/events",                              feed_type: "web",        fetch_interval_hours: 48 },
  { name: "Eventbrite Coventry",    url: "https://www.eventbrite.co.uk/d/united-kingdom--coventry/events/",  feed_type: "eventbrite", fetch_interval_hours: 24 },
  { name: "Humanitix Coventry",     url: "https://events.humanitix.com/uk/coventry",                         feed_type: "web",        fetch_interval_hours: 24 },
  { name: "Coventry Music",         url: "https://www.coventrymusic.co.uk/events",                           feed_type: "web",        fetch_interval_hours: 48 },
  { name: "Cheylesmore Library",    url: "https://cheylesmorecentre.co.uk/library-events/",                  feed_type: "web",        fetch_interval_hours: 48 }
].each do |attrs|
  Feed.find_or_create_by!(url: attrs[:url]) do |f|
    f.assign_attributes(attrs.merge(active: true))
  end
end

puts "Feeds seeded: #{Feed.count}"
