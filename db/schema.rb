# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_15_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "events", force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", null: false
    t.string "date_text"
    t.string "event_url"
    t.string "first_seen"
    t.string "last_seen"
    t.string "name", null: false
    t.integer "times_listed", default: 1
    t.datetime "updated_at", null: false
    t.string "venue"
    t.index ["category"], name: "index_events_on_category"
    t.index ["name", "venue"], name: "index_events_on_name_and_venue", unique: true
    t.index ["venue"], name: "index_events_on_venue"
  end

  create_table "sources", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "date_range"
    t.datetime "published_at"
    t.string "source_type", default: "reddit", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.integer "week_number"
    t.index ["source_type"], name: "index_sources_on_source_type"
    t.index ["url"], name: "index_sources_on_url", unique: true
    t.index ["week_number"], name: "index_sources_on_week_number"
  end
end
