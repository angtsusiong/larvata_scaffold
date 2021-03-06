class <%= 'Admin::' if admin? %><%= controller_class_name %>Controller < ApplicationController
<% if admin? -%>
  layout "admin"
<% end -%>

  before_action :set_<%= singular_name %>, only: [:show, :edit, :update, :destroy, :change_show_tab, :render_tab_content]
  before_action :set_navigation, only: [:new, :edit, :show, :destroy]
  before_action :class_authorize, only: [:index, :new, :create]

  def index
<% unless tab.nil? -%>
    <%= "@#{controller_file_name}_#{tab}_group_row_counts = #{class_name}.group(:#{tab}).count" %>
    @<%= controller_file_name %>_all_row_count = @<%= controller_file_name %>_<%= tab %>_group_row_counts.inject(0) { |row_count, <%= tab %>_group| row_count + <%= tab %>_group[1] }
<% end -%>
    session[:navigation] = []
  end

  def datatables
<% if enable_pundit? -%>
    <%= "authorize [:admin, #{class_name}], :index?" if admin? %>
    <%= "authorize #{class_name}, :index?" unless admin? %>
<% end -%>

    respond_to do |format|
      # 設定排序條件
      unless params[:order].blank?
        params[:order].each do |k,v|
          @order_columns ||= []
          @order_columns << "#{params[:columns][ v[:column] ][:data]} #{ v[:dir] }".gsub('_i18n', '')
        end
      end

      @page = (params[:start].to_i/params[:length].to_i) + 1 # 要顯示資料的頁數

      @filters = DatatablesService.new({class_name: "<%= class_name %>"}).handle_filters(params)

      @keyword = params[:search][:value] unless params[:search].blank?
      @filters["id_cont".to_sym] = @keyword if @keyword

      class_scope = <%= 'Admin::' if admin? %><%= class_name %>Policy::Scope.new(current_user, <%= class_name %>).resolve
      active_record_query = class_scope 
      @q = active_record_query.ransack(@filters)

      @q.sorts = @order_columns.empty? ? ["updated_at desc"] : @order_columns

      @<%= plural_name %> = @q.result.page(@page).per(params[:length])
      @filtered_count = @q.result.count
      @total_count = active_record_query.count

      format.json {
        render json: {
          recordsTotal: @total_count, # 資料總筆數
          recordsFiltered: @filtered_count, # 過濾後資料筆數
          data: to_datatables(@<%= plural_name %>) # 整理查詢結果
        }
      }
    end
  end

  def new
    @<%= singular_name %> ||= <%= class_name %>.new
  end

  def create
    @<%= singular_name %> = <%= class_name %>.new(<%= singular_name %>_params)
    respond_to do |format|
      if @<%= singular_name %>.save
        # 更新已上傳、但未設定 attachable_id 的檔案資料
        Attachment.update_attachable_ids(params[:attachments], @<%= singular_name %>.id)

        format.html {
          flash[:notice] = I18n.t('helpers.form.create_success', model: <%= class_name %>.model_name.human)
          back
        }

        format.js {}
      else
        format.html {
          render :new
        }

        format.js {}
      end
    end
  end

  def edit

  end

  def show
    @tabs = tabs
  end

  def update
    respond_to do |format|
      if @<%= singular_name %>.update(<%= singular_name %>_params)
        format.html {
          flash[:notice] = I18n.t('helpers.form.update_success', model: <%= class_name %>.model_name.human)
          back
        }

        format.js {}
      else
        format.html {
          render :edit
        }

        format.js {}
      end
    end
  end

  def destroy
    @<%= singular_name %>.destroy

    respond_to do |format|
      format.html {
        flash[:notice] = I18n.t('helpers.form.destroy_success', model: <%= class_name %>.model_name.human)
        back
      }

      format.js {}
    end
  end

<% if enable_row_editor? -%>
  # 更新列表的單筆 row 資料
  def update_row
    params[:data].each do |id, column_values|
      respond_to do |format|
        format.json {
          <%= singular_name %> = <%= class_name %>.find_by(id: id)

<% if enable_pundit? -%>
          <%= "authorize [:admin, #{singular_name}]" if admin? %>
          <%= "authorize #{singular_name}" unless admin? %>
<% end -%>

          <%= singular_name %>_params = <%= singular_name %>_row_params(column_values)

          if <%= singular_name %>&.update(<%= singular_name %>_params)
            <%= plural_name %> = <%= class_name %>.where(id: id)
            render json: {data: to_datatables(<%= plural_name %>)}
          end
        }
      end
    end
  end
<% end -%>

<% if contains_sorting_column? -%>
  # 更新列表的排序
  def update_row_sorting
    params[:rows_sorting]&.each{|id, sorting|
      <%= singular_name %> = <%= class_name %>.find_by(id: id)
      <%= singular_name %>&.send(:sorting=, sorting)
      <%= singular_name %>&.save
    }
  end
<% end -%>

<% # 建立 belongs_to associations select2 options method
editable_attributes_and_except_sorting_and_datetime_and_number.each do |attr|
  belongs_to_assoc = association_by_foreign_key(attr)
  if belongs_to_assoc
    assoc_class_name = belongs_to_assoc.name.to_s.classify
    assoc_singular_name = belongs_to_assoc.name.to_s
    assoc_plural_name = assoc_singular_name.pluralize
%>
  def <%= assoc_plural_name %>_for_select2
    per = params[:per]
    page = params[:page]
    filter = params[:search]

    q = <%= assoc_class_name %>.ransack(id_eq: filter)
    q.sorts = "created_at desc"
    <%= assoc_plural_name %> = q.result.page(page).per(per)

    filtered_count = q.result.count

    <%= assoc_plural_name %> = <%= assoc_plural_name %>.map{|<%= assoc_singular_name%>| {id: <%= assoc_singular_name%>.id, text: <%= assoc_singular_name%>.id}}

    render json: {results: <%= assoc_plural_name %>, filtered_count: filtered_count, per: per}
  end
<%
  end
end
%>

  # 設定連結所屬明細頁籤
  def tabs
    tabs_array = []
    tabs_array << {name: '<%= master_controller %>'}
    tabs_array
  end

  # 變換頁籤顯示內容
  def change_show_tab
    @current_tab = tabs.select{ |tab| tab[:name] == params[:tab] }.first

    @current_tab = tabs.first if @current_tab.nil?

    row_count_vars_of_tab(@current_tab[:name])

    respond_to do |format|
      format.js {}
    end
  end

  def render_tab_content
    master_show_tab = params[:master_show_tab]

    master_show_tab = tabs.first[:name] if tabs.select{ |tab| tab[:name] == master_show_tab }.count == 0

    row_count_vars_of_tab(master_show_tab)

    render partial: "<%= 'admin/' if admin? %><%= controller_file_path %>/tabs/#{master_show_tab}_tab", locals: { <%= singular_name %>: @<%= singular_name %>, master_show_tab: master_show_tab }
  end

  def back
    _navigation = session[:navigation].pop
    redirect_to <%= "#{'admin_' if admin?}#{controller_file_path}_path" %> if _navigation.nil?
    redirect_to "#{_navigation[:master_show_url] || _navigation['master_show_url']}?master_show_tab=#{_navigation[:master_show_tab] || _navigation['master_show_tab']}&ignore_set_navigation=true" unless _navigation.nil?
  end

  private

  def set_<%= singular_name %>
    @<%= singular_name %> = <%= class_name %>.find(params[:id])
<% if enable_pundit? -%>
    <%= "authorize [:admin, @#{singular_name}]" if admin? %>
    <%= "authorize @#{singular_name}" unless admin? %>
<% end -%>
  end

  def <%= singular_name %>_params
    params.require(:<%= singular_name %>).permit(<%= editable_attributes.map{ |attr| ":#{attr.name}"}.join(', ') %>)
  end

  def <%= singular_name %>_row_params(column_values)
    column_values.permit(<%= editable_attributes.map{ |attr| ":#{attr.name}"}.join(', ') %>)
  end

  # 處理呈現在datatable的資料結構
  def to_datatables(<%= plural_name %>)
    <%= plural_name %>.map do |<%= singular_name %>|
      {
        DT_RowId: "#{<%= singular_name %>.id}",
        <%= all_attributes.map{ |attr|
          if is_enum? attr
            row_attr = "#{attr.name}: #{singular_name}.#{attr.name},\n        "
            row_attr += "#{attr.name}_i18n: #{singular_name}.#{attr.name}_i18n,"
            row_attr
          elsif attr.type == 'boolean'
            "#{attr.name}: #{singular_name}.#{attr.name} == true ? I18n.t('helpers.select.true_option') : I18n.t('helpers.select.false_option'),"
          elsif attr.type == 'datetime'
            "#{attr.name}: #{singular_name}.#{attr.name}&.strftime('%F %T'),"
          else
            "#{attr.name}: #{singular_name}.#{attr.name},"
          end
        }.join("\n        ")
        %>
      }
    end
  end

  def set_navigation
    return if params[:ignore_set_navigation]

    referrer = request.referrer
    return if referrer.blank?

    session[:navigation] ||= []
    _navigation = {}
    _navigation[:master_show_url] = referrer[0, referrer.index('?') || referrer.length]
    _navigation[:master_show_tab] = params[:master_show_tab]
    session[:navigation] << _navigation
  end

  # 計算列表頁面上的資料筆數統計值
  def row_count_vars_of_tab(tab_name)
    case tab_name
    when '<%= master %>'
    end
  end

<% if enable_pundit? -%>
  def class_authorize
    <%= "authorize [:admin, #{class_name}]" if admin? and custom_controller.nil? %>
    <%= "authorize #{class_name}" if not admin? and custom_controller.nil? %>

    <%= "authorize [:admin, :#{custom_controller}]" if admin? and custom_controller.present? %>
    <%= "authorize :#{custom_controller}" if not admin? and custom_controller.present? %>
  end
<% end -%>
end
