# encoding: utf-8

class MeetingAgendaReport < Prawn::Document

  include Redmine::I18n

  def to_pdf(object)
    set_font_families
    set_page_counter

    # Логотип и информация о компании
    if object.meeting_company.present?
      print_company_info(object.meeting_company)
      move_down 20
    end

    # Информация с согласующими и утверждающим
    print_approval_list(object.approvers, object.asserter)
    move_down 5

    # Информация о совещании (номер) и повестке (дата, время, место, адрес и тд)
    print_agenda_fields(object)
    move_down 10

    # Приглашенные участники совещания
    print_meeting_members(object.users)
    move_down 10

    # Внешние участники совещания
    if object.contacts.any?
      print_meeting_contacts(object.contacts)
      move_down 10
    end

    # Вопросы совещания
    print_meeting_questions(object.meeting_questions)

    render
  end

private

  def set_font_families
    fonts_path = "#{Rails.root}/plugins/redmine_meeting/lib/fonts/"
    font_families.update(
           "FreeSans" => { bold: fonts_path + "FreeSansBold.ttf",
                           italic: fonts_path + "FreeSansOblique.ttf",
                           bold_italic: fonts_path + "FreeSansBoldOblique.ttf",
                           normal: fonts_path + "FreeSans.ttf" },
            "Calibri" => { bold: fonts_path + "CALIBRIB.TTF",
                           italic: fonts_path + "CALIBRII.TTF",
                           bold_italic: fonts_path + "CALIBRIZ.TTF",
                           normal: fonts_path + "CALIBRI.TTF"}
                           )
    font "Calibri"
  end

  def set_page_counter
    page_options = {
      align: :right,
      start_count_at: 1,
      size: 8,
      family: 'Callibri',
      at: [bounds.right - 100, 0],
      inline_format: true
    }

    number_pages l(:label_page_counter), page_options
  end

  def print_company_info(company)
    image open(company.logo), vposition: :top, position: :center, fit: [400, 580]

    company_details = [
      [
        company.fact_address,
        company.phone,
        company.fax,
        company.email
      ], [
        company.okpo,
        company.inn,
        company.kpp,
        company.ogrn
      ]
    ]

    table company_details do |t|
        t.position = :center
        t.header = false
        t.width = 580
        t.cells.border_width = 0
        t.cells.size = 8
        t.cells.align = :center
        t.cells.valign = :middle
        t.cells.padding = [0,10,0,10]
        t.before_rendering_page do |page|
          page.row(0).border_top_width = 3
        end
    end
  end

  def print_approval_list(approvers, asserter)
    approval_list = [[
      {content: "«#{l(:label_meeting_protocol_head_agreed)}»"},
      nil,
      {content: "«#{l(:label_meeting_protocol_head_approved)}»"}
    ]]

    default_field = "_________________"
    agreed_list = (approvers.present? ? approvers : [default_field]).map{ |o| "#{o}/________/"}
    approved_list = (asserter.present? ? [asserter] : [default_field]).map{ |o| "#{o}/________/"}

    approval_list += agreed_list.zip([], approved_list)

    table approval_list do |t|
      t.position = :center
      t.header = false
      t.width = 580
      t.cells.border_width = 0
      t.cells.size = 10
      t.cells.style = :italic
#        t.cells.align = :right
      t.cells.valign = :middle
      t.cells.padding = [5,20,0,20]
      t.before_rendering_page do |page|
        page.column(0).align = :left
        page.column(2).align = :right
        page.row(0).font_style = :bold
      end
    end
  end

  def print_agenda_fields(agenda)
    text((agenda.is_external? ? l(:label_external_meeting_agenda) : l(:label_meeting_agenda)) + " №#{agenda.id}", style: :bold, size: 22, align: :center)
#    move_down 10

    text("<b>#{l(:field_subject)}:</b> <i>#{agenda.subject}</i>", size: 10, inline_format: true)
    text("<b>#{l(:field_external_company)}:</b> <i>#{agenda.external_company}</i>", size: 10, inline_format: true) if agenda.is_external?
    text("<b>#{agenda.is_external? ? l(:field_address) : l(:field_place)}:</b> <i>#{agenda.place}</i>", size: 10, inline_format: true)
    text("<b>#{l(:field_meet_on)}:</b> <i>#{format_date(agenda.meet_on)}</i>", size: 10, inline_format: true)
    text("<b>#{l(:label_meeting_agenda_time)}:</b> <i>#{format_time(agenda.start_time, false)} - #{format_time(agenda.end_time, false)}</i>", size: 10, inline_format: true)
    text("<b>#{l(:field_author)}:</b> <i>#{agenda.author}</i>", size: 10, inline_format: true)
  end

  def print_meeting_questions(questions)
    text("#{l(:label_meeting_question_plural)}:", size: 13, style: :bold)
#    move_down 5

    questions.group_by(&:project).sort_by{ |project, questions| project.to_s }.each do |project, questions|
      move_down 5
      text("#{project || l(:label_without_project)}", size: 10, style: :bold, align: :center)
#      move_down 5

      question_list = [[
        l(:label_meeting_question_title),
        l(:field_issue),
        l(:label_meeting_question_user),
        l(:field_status),
        l(:field_start_date),
        l(:field_due_date),
        l(:field_assigned_to)]]

      questions.each do |question|
        question_list << [
          "#{question}",
          "#{question.issue.to_s.gsub('#','№')}",
          "#{question.user}",
          "#{question.status if question.issue}",
          "#{format_date(question.issue.start_date) if question.issue}",
          "#{format_date(question.issue.due_date) if question.issue}",
          "#{question.issue.assigned_to if question.issue}"]
        question_list << [{content: question.description, colspan: 7}] if question.description.present?
      end

      table question_list, header: true, width: 580, position: :center, column_widths: {4 => 45, 5 => 60} do |t|
        t.cells.size = 8
#        t.cells.border_lines = [:dotted]*4
        t.cells.padding = [0,5,5,5]
        t.before_rendering_page do |page|
          page.column(0).align = :left
          page.column(1).align = :left
          page.column(2).align = :center
          page.column(2).valign = :center
          page.column(3).align = :center
          page.column(3).valign = :center
          page.column(4).align = :center
          page.column(4).valign = :center
          page.column(5).align = :center
          page.column(5).valign = :center
          page.column(6).align = :center
          page.column(6).valign = :center
          page.row(0).font_style = :bold
          page.row(0).background_color = "DDDDDD"
          page.row(0).align = :center
          page.row(0).valign = :center
        end
      end
    end
  end

  def print_meeting_contacts(contacts)
    text("#{l(:field_meeting_contacts)}:", size: 13, style: :bold)
    move_down 5

    meeting_contacts = contacts.map do |contact|
      [
        contact.company,
        contact.job_title,
        contact.name
      ]
    end

    meeting_contacts.insert(0, [
      l(:field_company),
      l(:field_job_title),
      l(:field_contact)])

    table meeting_contacts, header: true, width: 540, position: :center do |t|
        t.cells.size = 10
        t.cells.padding = [0,10,5,10]
        t.cells.align = :center
        t.cells.border_lines = [:dotted]*4
        t.before_rendering_page do |page|
          page.row(0).font_style = :bold
          page.row(0).background_color = "DDDDDD"
          page.row(0).align = :center
        end
    end
  end

  def print_meeting_members(users)
    text("#{l(:field_meeting_members)}:", size: 13, style: :bold)
    move_down 5

    meeting_members = users.map do |user|
      [
        user.company,
        user.job_title,
        user.name
      ]
    end

    meeting_members.insert(0, [
      l(:field_company),
      l(:field_job_title),
      l(:field_member)])

    table meeting_members, header: true, width: 540, position: :center do |t|
        t.cells.size = 10
        t.cells.padding = [0,10,5,10]
        t.cells.align = :center
        t.cells.border_lines = [:dotted]*4
        t.before_rendering_page do |page|
          page.row(0).font_style = :bold
          page.row(0).background_color = "DDDDDD"
          page.row(0).align = :center
        end
    end
  end
end