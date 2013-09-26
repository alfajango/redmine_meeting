class MeetingProtocolsController < ApplicationController
  unloadable

  helper :attachments
  include AttachmentsHelper
  helper :meeting_protocols
  include MeetingProtocolsHelper
  helper :meeting_issues
  include MeetingIssuesHelper
  helper :meeting_comments
  include MeetingCommentsHelper
  helper :meeting_approvers
  include MeetingApproversHelper


  before_filter :find_object, only: [:edit, :show, :destroy, :update, :send_notices, :resend_notices]
  before_filter :new_object, only: [:new, :create]

  def send_notices
    (render_403; return false) unless can_send_notices?(@object)
    @object.meeting_participators.each do |member|
      send_notice(member)
    end

    redirect_to controller: 'meeting_protocols', action: 'show', id: @object.id
  end

  def resend_notices
    (render_403; return false) unless can_send_notices?(@object)
    @object.meeting_participators.each do |member|
      resend_notice(member)
    end

    redirect_to controller: 'meeting_protocols', action: 'show', id: @object.id
  end

  def show
    (render_403; return false) unless can_show_protocol?(@object)
  end

  def index
    @limit = per_page_option

    @scope = model_class.joins(:meeting_agenda).
      time_period(params[:time_period_created_on], 'meeting_protocols.created_on').
      time_period(params[:time_period_meet_on], 'meeting_agendas.meet_on').
      eql_field(params[:author_id], 'meeting_protocols.author_id').
      eql_field(params[:created_on], 'DATE(meeting_protocols.created_on)').
      eql_field(params[:meet_on], 'meeting_agendas.meet_on').
      eql_project_id(params[:project_id]).
      like_field(params[:subject], 'meeting_agendas.subject').
      uniq

    @scope = @scope.joins(:meeting_participators).joins(:meeting_answers).where("meeting_participators.user_id = :user_id OR meeting_answers.reporter_id = :user_id", user_id: User.current.id) unless admin?

    @count = @scope.count

    @pages = begin
      Paginator.new @count, @limit, params[:page]
    rescue
      Paginator.new self, @count, @limit, params[:page]
    end
    @offset ||= begin
      @pages.offset
    rescue
      @pages.current.offset
    end

    @collection = @scope.
      limit(@limit).
      offset(@offset).
#      order(sort_clause).
      order('created_on desc').
      all
  end

  def new
    (render_403; return false) unless can_create_protocol?(@object)
    session[:meeting_participator_ids] = @object.meeting_agenda.user_ids
    session[:meeting_contact_ids] = @object.meeting_agenda.contact_ids
#    session[:meeting_watcher_ids] = @object.meeting_agenda.watcher_ids
    nested_objects_from_session

#    @object.meeting_answers_attributes = @object.meeting_agenda.meeting_questions.map do |question|
#      {meeting_question_id: question.id, reporter_id: question.user_id}
#    end
#    @object.meeting_participators_attributes = @object.meeting_agenda.meeting_members.map do |member|
#      {meeting_member_id: member.id, user_id: member.user_id}
#    end
  rescue
    render_403
  end

  def create
    (render_403; return false) unless can_create_protocol?(@object)
    @object.save_attachments(params[:attachments] || (params[:issue] && params[:issue][:uploads]))
    @object.meeting_participators_attributes = session[:meeting_participator_ids].map{ |user_id| {user_id: user_id} } if session[:meeting_participator_ids].present?
    @object.meeting_contacts_attributes = session[:meeting_contact_ids].map{ |contact_id| {contact_id: contact_id} } if session[:meeting_contact_ids].present?
    @object.meeting_watchers_attributes = session[:meeting_watcher_ids].map{ |user_id| {user_id: user_id} } if session[:meeting_watcher_ids].present?
    if @object.save
      flash[:notice] = l(:notice_successful_create)
      render_attachment_warning_if_needed(@object)
      redirect_to action: 'show', id: @object.id
    else
      nested_objects_from_session
      render action: 'new'
    end
  end

  def edit
    (render_403; return false) unless can_update_protocol?(@object)
    nested_objects_from_database
  end


  def update
    (render_403; return false) unless can_update_protocol?(@object)
    @object.save_attachments(params[:attachments] || (params[:issue] && params[:issue][:uploads]))
    if @object.update_attributes(params[model_sym])
      flash[:notice] = l(:notice_successful_update)
      render_attachment_warning_if_needed(@object)
      redirect_to action: 'show', id: @object.id
    else
      nested_objects_from_database
      render action: 'edit'
    end
  end

  def destroy
    (render_403; return false) unless can_destroy_protocol?(@object)
    flash[:notice] = l(:notice_successful_delete) if @object.destroy
    redirect_to action: 'index'
  end

private
  def nested_objects_from_session
    @members = User.active.sorted.find(session[:meeting_participator_ids])
    @contacts = Contact.order_by_name.find(session[:meeting_contact_ids])
#    @watchers = User.active.sorted.find(session[:meeting_watcher_ids])
  end

  def nested_objects_from_database
    @members = @object.users
    @contacts = @object.contacts
#    @watchers = @object.watchers
  end

  def model_class
    MeetingProtocol
  end

  def model_sym
    :meeting_protocol
  end

  def find_object
    @object = model_class.find(params[:id])
  end

  def new_object
    @object = model_class.new(params[model_sym])
  end

  def send_notice(member)
    member.update_attribute(:issue_id, create_issue(member).try(:id))
#  rescue
  end

  def resend_notice(member)
    cancel_status_id = IssueStatus.find(Setting[:plugin_redmine_meeting][:cancel_issue_status]).id
    if member.issue.present?
      member.issue.update_attribute(:status_id, cancel_status_id)
      member.update_attribute(:issue_id, nil)
      send_notice(member)
    end
#  rescue
  end

  def key_words
    {
      id: @object.id,
      subject: @object.meeting_agenda.subject,
      meet_on: @object.meeting_agenda.meet_on.strftime("%d.%m.%Y"),
      start_time: @object.meeting_agenda.start_time.strftime("%H:%M"),
      end_time: @object.meeting_agenda.end_time.strftime("%H:%M"),
      author: @object.author,
      place: @object.meeting_agenda.place,
      url: url_for(controller: 'meeting_protocols', action: 'show', id: @object.id)
    }
  end

  def put_key_words(template)
    key_words.inject(template){ |result, key_word|
      result.gsub("%#{key_word[0]}%", "#{key_word[1]}")
    }
  end

  def issue_subject
    put_key_words(Setting[:plugin_redmine_meeting][:notice_subject])
  end

  def issue_description
    put_key_words(Setting[:plugin_redmine_meeting][:notice_description])
  end

  def create_issue(member)
    settings = Setting[:plugin_redmine_meeting]
    Issue.create(
      status: IssueStatus.default,
      tracker: Tracker.find(settings[:notice_issue_tracker]),
      subject: issue_subject,
      project: Project.find(settings[:notice_project_id]),
      description: issue_description,
      author: User.current,
      start_date: @object.meeting_agenda.meet_on,
      due_date: @object.meeting_agenda.meet_on + settings[:notice_duration].to_i.days,
      priority: @object.meeting_agenda.priority || IssuePriority.default,
      assigned_to: member.user)
  end
end
