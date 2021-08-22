require 'active_record'
require 'pg'
require 'csv'
require 'json'

# Script to update information in the database for Pingry Covid-19 Tracking
# Author: Drew Beckmen

credentials = File.read('credentials.json')
credentials_hash = JSON.parse(credentials)

ActiveRecord::Base.establish_connection(
  adapter:    'postgresql',
  host:       credentials_hash['host'],
  database:   credentials_hash['database'],
  username:   credentials_hash['username'],
  password:   credentials_hash['password'],
  port:       credentials_hash['port']
)

class Student < ActiveRecord::Base
  self.table_name = 'students'
end

# Let's deal with teachers first
teachers = CSV.parse(File.read('staff.csv'), headers: true)
ids = teachers.by_col[0]

# Adds a new teacher to the database
def add_teacher(first, last, campus, veracross, email)
  puts("Adding #{first} #{last} #{campus} #{veracross} #{email}")
  Student.create(
    first_name: first,
    last_name: last,
    campus: campus,
    veracross_id: veracross,
    email: email,
    teacher: true
  )
end

def mark_new_returning_teachers(teachers)
  number_added = 0
  teachers.each do |row|
    search_key = row['Person ID']
    find = Student.where(veracross_id: search_key).first
    if find.nil?
      veracross_id = row['Person ID']
      full_name = row['Full Name'].split(',')
      last_name, first_name = full_name[0].strip(), full_name[1].strip()
      email = row['Email']
      campus = row['Primary School'] == 'Short Hills' ? 'Short Hills' : 'Basking Ridge'
      add_teacher(first_name, last_name, campus, veracross_id, email)
      row['Status'] = 'Added'
      number_added += 1
    else
      row['Status'] = 'Verified'
    end
  end
  puts("Finished adding #{number_added} teachers")
  # Write out the updates:
  CSV.open("staff.csv", "w") do |f|
    f << teachers.headers
    teachers.each{|row| f << row}
  end
end

def retire_old_teachers(current_teacher_ids)
  to_retire = Student.where.not(veracross_id: current_teacher_ids)
  teachers = to_retire.select{|person| person.teacher }
  number_retired = 0
  teachers.each do |teacher|
    # by default, we will assume grade 13 is someone no longer present at the school
    teacher.grade = 13
    number_retired += 1
    teacher.save!
    puts("Retired teacher #{teacher.first_name} #{teacher.last_name}")
  end
  puts("Retired #{number_retired} teachers no longer at the school.")
end

def update_teachers(teachers, ids)
  mark_new_returning_teachers(teachers)
  retire_old_teachers(ids)
end

update_teachers(teachers, ids)