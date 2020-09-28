require 'date'

lines = []

ARGV.each do |filename|
  lines << File.readlines(filename)
end

lines.flatten!

STDERR.puts "Read #{ARGV.count} logfiles successfully. Starting analysis..."

header = /^(?<time>.*)\sGMT.*automatic vacuum of table "(?<table>.*?)"/
pages  = /pages:\s(?<removed>\d+)\sremoved,\s(?<remain>\d+)\sremain,\s(?<skippedpins>\d+).*(?<skippedfrozen>\d+)\sskipped frozen/
tuples = /tuples:.*?(?<removed>\d+)\sremoved.*?(?<remain>\d+)\sremain.*?(?<dead>\d+)\sare dead/
buffer = /buffer.*?(?<hits>\d+)\shits.*?(?<misses>\d+)\smisses.*?(?<dirtied>\d+)\sdirtied/
io     = /avg read rate: (?<read>[\d\.]+)\s.*?avg write rate: (?<write>[\d\.]+)\s.*?/
system = /system.*?user: (?<user>[\d\.]+)\s.*?system: (?<system>[\d\.]+)\s.*?elapsed: (?<real>[\d\.]+)/

vacuums = []

STDERR.puts "Parsing lines..."

lines.each_with_index do |line, i|

  # binding.pry

  # If we have a vacuum line then kick off the process
  if matches = line.match(header)
    entry = {}
    entry[:time] = matches[:time]
    entry[:table] = matches[:table]

    if pages_match = lines[i+1].match(pages)
      entry[:removed_pages] = pages_match[:removed]
      entry[:remain_pages] = pages_match[:remain]
      entry[:skippedpins] = pages_match[:skippedpins]
      entry[:skippedfrozen] = pages_match[:skippedfrozen]
    else
      next
    end

    if tuples_match = lines[i+2].match(tuples)
      entry[:removed_tuples] = tuples_match[:removed]
      entry[:remain_tuples] = tuples_match[:remain]
      entry[:dead] = tuples_match[:dead]
    else
      next
    end

    if buffer_match = lines[i+3].match(buffer)
      entry[:hits] = buffer_match[:hits]
      entry[:misses] = buffer_match[:misses]
      entry[:dirtied] = buffer_match[:dirtied]
    else
      next
    end

    if io_match = lines[i+4].match(io)
      entry[:read] = io_match[:read]
      entry[:write] = io_match[:write]
    else
      next
    end

    if system_match = lines[i+5].match(system)
      entry[:user] = system_match[:user]
      entry[:system] = system_match[:system]
      entry[:real] = system_match[:real]
    else
      next
    end

    vacuums << entry
  end
end

STDERR.puts "Grouping vacuums into hourly blocks..."

grouped = vacuums.group_by do |vacuum|
  DateTime.parse(vacuum[:time]).strftime("%Y-%m-%d")
end

headers = [
  "Day",
  "Number of Log Entries",
  "Total Vacuuming Time (s)",
  "Vacuum Load Average",
  "Total Removed Tuples",
  "Total Buffer Hits",
  "Total Buffer Misses",
  "Total Buffer Dirtied",
  "Average Read Rate (MB/s)",
  "Average Write Rate (MB/s)",
]

STDERR.puts "PRINTING CSV! 🍺 🥳 "

STDOUT.puts headers.join(',')

grouped.each do |time, details|
  details.uniq!

  r = []

  # Day
  r << time

  # Number of Log Entries
  r << details.length

  # Total Vacuuming Time (s)
  totaltime = details.map{|d| d[:real].to_f }.sum
  r << totaltime

  # Vacuum Load Average (Total number of hours spendt vacuuming during this hour)
  vla = totaltime / 60 / 60 / 24
  r << vla

  # Total Removed Tuples
  r << details.map{|d| d[:removed_tuples].to_i }.sum

  # Total Buffer Hits
  r << details.map{|d| d[:hits].to_i }.sum

  # Total Buffer Misses
  r << details.map{|d| d[:misses].to_i }.sum

  # Total Buffer Dirtied
  r << details.map{|d| d[:dirtied].to_i }.sum

  # Average Read Rate (MB/s)
  total_read = details.map{|d| d[:read].to_f }.sum
  r << (total_read.to_f / details.count)

  # Average Write Rate (MB/s)
  total_write = details.map{|d| d[:write].to_f }.sum
  r << (total_write.to_f / details.count)

  STDOUT.puts r.join(',')
end
