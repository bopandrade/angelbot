#!/usr/bin/env ruby
require 'cgi'
require 'timeout'
require 'capybara'
require 'capybara/dsl'
require 'capybara/poltergeist'
require 'set'
require 'json'

class JobHunter
  def initialize(driver = :selenium)
    @s = Capybara::Session.new(driver)
    if driver == :selenium
      @s.driver.class.class_eval { def quit; end }
    elsif driver == :poltergeist
      @s.driver.browser.js_errors = false
    end
    
    @@no_locations = Set.new []

    @@locations = Set.new ['San Francisco', 'Oakland', 'Santa Clara', 'Palo Alto',
                           'San Francisco Bay Area', 'Millbrae', 'Foster City', 'Los Angeles', 
                           'Stanford', 'Mountain View', 'Sunnyvale', 'Silicon Valley',
                           'Sacramento', 'Berkeley', 'Remote', 'San Ramon', 'San Mateo',
                           'Redwood City', 'San Leandro', 'San Diego']
    @@job_generic = Set.new ['Enginner', 'Developer']
    @@job_need = Set.new ['Backend', 'Stack', 'Fullstack', 'QA', 'Data', 'BackEnd', 'Software',
                          'Machine', 'Server', 'Solutions', 'Site', 'Reliability', 'Security',
                          'Operations', 'Product', 'Platform', 'DevOps', 'Ruby', 'Learning',
                          'Back', 'Web', 'Autonomy', 'App', 'Game', 'Infrastructure',
                          'Quality', 'Assurance']
    @@job_block = Set.new ['Art', 'Creative', 'Frontend', 'UX', 'UI', 'Marketing', 'Video',
                           'Front', 'Head', 'Lead', 'Director', 'Scala']

    @@message = ",\n\nMy name is Bruno and since I was 12 I started programming to automate multiple tasks.\n\nAs it happens, this application was also submitted by a program. The code is available at bopandrade.com/angelbot\n\nIf this message finds you and piques your interest, hit me up!\n\nThanks for your time,\n\nBruno"
  end
  def debug?
    begin
      while c = STDIN.read_nonblock(1)
        return true if c == 'd'
      end
      false
    rescue Errno::EINTR
      false
    rescue Errno::EAGAIN
      false
    rescue EOFError
      false 
    end
  end

  def job_match(job_div)
    job_name = job_div.find(:css, 'div.title').text.gsub(/[^0-9a-z ]/i, ' ')
    if matcher(job_div.find(:css, 'div.tags').text, '·', @@locations) &&
        matcher(job_name, ' ', @@job_need) &&
        !matcher(job_name, ' ', @@job_block)
      return true
    elsif matcher(job_name, ' ', @@job_generic)
      job_name = job_div.find(:css, 'div.tags').text
      if matcher(job_name, '·', @@locations) &&
          matcher(job_name, '·', @@job_need) &&
          !matcher(job_name, '·', @@job_block)
        return true
      end
    end
    return false

  end


  def matcher(string,splitCh,set)
    return string.split(splitCh).map(&:strip).to_set.intersect?(set)
  end

  def login
    @s.click_link('Log In')

    u = ENV['AL_EMAIL'] || nil
    p = ENV['AL_PASSWORD'] || nil

    if u == nil || p == nil
      puts "Please set environment values for AL_EMAIL and AL_PASSWORD"
      exit
    end

    @s.find('#user_email').set(u)
    @s.find('#user_password').set(p)

    @s.find('input[name="commit"]').click
  end

  def visit(link)
    @s.visit(link)
  end

  def logged_in?
    return @s.has_selector?('img[class="angel_image"]')
  end

  def session
    return @s
  end

  def archive(current_listing)
    current_listing.find(:css, 'a.archive-button').click
    sleep 2
  end

  def data_dump(data, file)
    File.open(file,"w") do |f|
      f.write(JSON.pretty_generate(data))
    end
  end

  def debugnow
    while true
      puts 'Insert command:'
      begin
        s = gets.chomp
        break if s == 'break'
        eval s

      rescue StandardError => error
        puts error
      end
    end
  end

  def work
    link = 'https://angel.co/jobs'
    while true
      begin
        while !logged_in?
          visit(link)
          login
        end
        if session.has_no_css?('.job_listings.expanded')
          sleep 10
        end
        if session.has_no_css?('.job_listings.expanded')
          puts "Could not find job listing"
          visit(link)
          next
        end
        debugnow if debug?
        current_listing = session.find(:css, '.job_listings.expanded')
        if !matcher(current_listing.find(:css,'.tag.locations.tiptip').text,',',@@locations)
          archive(current_listing)
          @@no_locations.merge(current_listing.find(:css,'.tag.locations.tiptip').text.split(',').map(&:strip))
          next
        end

        jobs = current_listing.all(:css, 'div.listing-row')
        jobs_apply = []
        0.upto(jobs.length - 1) do |i|
          jobs_apply.push(job_match(jobs[i]))
        end

        if !jobs_apply.any?
          archive(current_listing)
          next
        end

        current_listing.find(:css, 'a.interested-button').click

        while current_listing.has_css?('a.interested-button.c-button--loading')
          current_listing.find(:css, 'div.js-done').click if current_listing.has_css?('div.js-done')
          puts 'still has interested button'
          sleep 2
        end

        while session.has_no_css?('div.post_candidate_applied') &&
            session.has_no_css?('textarea.interested-note')
          sleep 2
          puts 'while no post candidate applied'
        end


        if session.has_css?('a.js-note-link') && session.has_no_css?('textarea.interested-note')
          session.find(:css, 'a.js-note-link').click 
        end
        sleep 2
        if session.has_css?('textarea.interested-note')
          textarea = session.find(:css, 'textarea.interested-note')

          if textarea['placeholder'] =~ /Enter a note to (.+?) at /
            message = "Hi " + $1 + @@message
            while textarea.value !~ /Thanks for your time/
              textarea.set(message)
              sleep 2
            end
            session.find(:css, 'a.interested-with-note-button').click
            while session.has_css?('textarea.interested-note')
              sleep 2
            end
          end
        end

        while session.has_no_css?('div.post_candidate_applied')
          sleep 2
          debugnow
        end

        next if jobs.count == 1

        post_apply = session.find(:css, 'div.post_candidate_applied')

        interested = post_apply.all(:css, 'label.interested')
        not_interested = post_apply.all(:css, 'label.not-interested')

        0.upto(jobs.length - 1) do |i|
          jobs_apply[i] ? interested[i].click : not_interested[i].click
        end

      rescue StandardError => error
        puts error
        puts error.backtrace
        puts 'error < exception variable'
        debugnow
      end

    end


  end
end

#jh = JobHunter.new(:poltergeist)
jh = JobHunter.new
jh.work

=begin

s.find('#sign-in-email').set(ENV.fetch('EMAIL'))
s.find(:xpath, '//input[@type="password"]').set(ENV.fetch('PASSWORD'))
s.find('.hw-btn-primary').click

s.all('.confirmation-code').each do |code|
  puts code.text
end

images = GoogleImagesSearcher.new.find_sites_with_image ARGV[0]

puts "Found #{images.count} pages using this image:"
images.each do |img|
  puts img
end
=end
