module ZoneDetectable
  extend ActiveSupport::Concern

  COVENTRY_POSITIVE = /\bcoventry\b|warwick\s+arts\s+centre|university\s+of\s+warwick/i

  BIRMINGHAM_PATTERN = /\b(
    birmingham|brum|digbeth|moseley|kings?\s*heath|wolverhampton|
    sutton\s+coldfield|west\s*brom(wich)?|walsall|handsworth|erdington|
    edgbaston|smethwick|selly\s+oak|stirchley|harborne|
    jewellery\s+quarter|bearwood|stourbridge|halesowen|
    solihull|cannock|lichfield
  )\b/xi

  WARWICKSHIRE_PATTERN = /\b(
    leamington(\s+spa)?|warwick|bedworth|kenilworth|nuneaton|
    rugby|stratford(-upon-avon)?|atherstone|southam|harbury|
    lighthorne|napton|moreton\s+morrell|long\s+itchington|
    alcester|shipston|coleshill|henley.in.arden|
    fillongley|meriden|balsall\s+common|hampton.in.arden
  )\b/xi

  class_methods do
    def detect_zone(text)
      t = text.to_s
      return "coventry"     if t.match?(COVENTRY_POSITIVE)
      return "birmingham"   if t.match?(BIRMINGHAM_PATTERN)
      return "warwickshire" if t.match?(WARWICKSHIRE_PATTERN)
      "coventry"
    end
  end
end
