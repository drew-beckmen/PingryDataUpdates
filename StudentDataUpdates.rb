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

GRADE_MAP = {
  'Kindergarten' => 0,
  'Grade 1' => 1,
  'Grade 2' => 2,
  'Grade 3' => 3,
  'Grade 4' => 4,
  'Grade 5' => 5,
  'Grade 6' => 6,
  'Form I' => 7,
  'Form II' => 8,
  'Form III' => 9,
  'Form IV' => 10,
  'Form V' => 11,
  'Form VI' => 12,
}

class Student < ActiveRecord::Base
  self.table_name = 'students'
end


students = CSV.parse(File.read('students.csv'), headers: true)
veracross_ids = students.by_col[0]

def load_student(first, last, campus, veracross, grade)
  puts("Adding #{first} #{last} #{campus} #{veracross} Grade #{grade}")
  Student.create(
    first_name: first,
    last_name: last,
    campus: campus,
    veracross_id: veracross,
    teacher: false
  )
end

def update_grades_add_new(students)
  number_added = 0
  number_updated = 0
  students.each do |row|
    search_key = row['Person ID']
    find = Student.where(veracross_id: search_key).first
    if find.nil?
      # entirely new student needs to be added
      veracross_id = row['Person ID']
      last_name, first_name = row['Last Name'].strip, row['First Name'].strip
      grade = GRADE_MAP[row['Current Grade']]
      campus = row['Campus'] == 'Short Hills' ? 'Short Hills' : 'Basking Ridge'
      load_student(first_name, last_name, campus, veracross_id, grade)
      row['Status'] = 'Added'
      number_added += 1
    else
      # need to update the grade and campus for new school year
      database_grade = find.grade
      if database_grade != row['Current Grade']
        new_grade = GRADE_MAP[row['Current Grade']]
        new_campus = new_grade <= 5 ? 'Short Hills' : 'Basking Ridge'
        puts("Updated grade for #{find.first_name} #{find.last_name} from #{database_grade} to #{new_grade}")
        find.grade = new_grade
        find.campus = new_campus
        find.save!
        number_updated += 1
        row['Status'] = 'Updated Grade'
      else
        row['Status'] = 'Verified'
      end
    end
  end
  puts("Finished adding #{number_added} students")
  puts("Finished updating #{number_updated} grades and/or campuses")
  # Write out the updates:
  CSV.open("students.csv", "w") do |f|
    f << students.headers
    students.each{|row| f << row}
  end
end

def retire_old_students(current_student_ids)
  to_retire = Student.where.not(veracross_id: current_student_ids)
  students = to_retire.select{|person| !person.teacher }
  number_retired = 0
  students.each do |student|
    # by default, we will assume grade 13 is someone no longer present at the school
    student.grade = 13
    number_retired += 1
    student.save!
    puts("Retired student #{student.first_name} #{student.last_name}")
  end
  puts("Retired #{number_retired} students no longer at the school.")
end

def update_students(students, ids)
  update_grades_add_new(students)
  retire_old_students(ids)
end

update_students(students, veracross_ids)
