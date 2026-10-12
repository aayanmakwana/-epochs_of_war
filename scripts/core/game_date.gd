class_name GameDate
extends RefCounted
## Calendar helpers. The game clock is stored as a day index counted from
## EPOCH (1 January 1936 = day 0) plus an hour 0-23. That keeps save files and
## comparisons trivial; convert to a calendar date only for display.

const EPOCH_YEAR := 1936
const MONTH_NAMES: PackedStringArray = ["January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"]
const MONTH_SHORT: PackedStringArray = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


static func is_leap_year(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0


static func days_in_year(year: int) -> int:
	return 366 if is_leap_year(year) else 365


static func days_in_month(year: int, month: int) -> int:
	match month:
		2:
			return 29 if is_leap_year(year) else 28
		4, 6, 9, 11:
			return 30
		_:
			return 31


## Day index -> {"year", "month" (1-12), "day" (1-31)}.
static func from_index(day_index: int) -> Dictionary:
	var year := EPOCH_YEAR
	var rem := day_index
	while rem >= days_in_year(year):
		rem -= days_in_year(year)
		year += 1
	while rem < 0:
		year -= 1
		rem += days_in_year(year)
	var month := 1
	while rem >= days_in_month(year, month):
		rem -= days_in_month(year, month)
		month += 1
	return {"year": year, "month": month, "day": rem + 1}


## Calendar date -> day index.
static func to_index(year: int, month: int, day: int) -> int:
	var idx := 0
	if year >= EPOCH_YEAR:
		for y in range(EPOCH_YEAR, year):
			idx += days_in_year(y)
	else:
		for y in range(year, EPOCH_YEAR):
			idx -= days_in_year(y)
	for m in range(1, month):
		idx += days_in_month(year, m)
	return idx + day - 1


## "1 January 1936" (or "1 January 1936, 14:00" when hour >= 0).
static func format(day_index: int, hour: int = -1) -> String:
	var d := from_index(day_index)
	var s := "%d %s %d" % [d.day, MONTH_NAMES[d.month - 1], d.year]
	if hour >= 0:
		s += ", %02d:00" % hour
	return s


## "1 Jan 1936"
static func format_short(day_index: int) -> String:
	var d := from_index(day_index)
	return "%d %s %d" % [d.day, MONTH_SHORT[d.month - 1], d.year]
