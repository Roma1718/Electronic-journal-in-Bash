#!/bin/bash

VERSION="1.0.0"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$BASE_DIR/data"
USERS_DIR="$DATA_DIR/users"
COURSES_DIR="$DATA_DIR/courses"
EXPORTS_DIR="$BASE_DIR/exports"
BACKUPS_DIR="$BASE_DIR/backups"
LOGS_DIR="$BASE_DIR/logs"
LOG_FILE="$LOGS_DIR/journal.log"

CURRENT_USER=""
CURRENT_TEACHER=""
CURRENT_COURSE=""
CURRENT_GROUP=""

print_header() {
    clear
    echo "=========================================="
    echo "          ЭЛЕКТРОННЫЙ ЖУРНАЛ"
    echo "=========================================="
}

print_error() {
    echo
    echo "ОШИБКА: $1"
    echo
}

print_success() {
    echo
    echo "УСПЕШНО: $1"
    echo
}

pause() {
    echo
    read -r -p "Нажмите Enter для продолжения..."
}

write_log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $message" >> "$LOG_FILE"
}

init_project() {
    mkdir -p "$USERS_DIR"
    mkdir -p "$COURSES_DIR"
    mkdir -p "$EXPORTS_DIR"
    mkdir -p "$BACKUPS_DIR"
    mkdir -p "$LOGS_DIR"
    touch "$LOG_FILE"
}

hash_password() {
    local password="$1"
    printf "%s" "$password" | sha256sum | awk '{print $1}'
}

valid_date() {
    local input_date="$1"

    if [[ ! "$input_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        return 1
    fi

    date -d "$input_date" "+%Y-%m-%d" >/dev/null 2>&1
}

register_teacher() {
    print_header
    echo "=== РЕГИСТРАЦИЯ ПРЕПОДАВАТЕЛЯ ==="
    echo

    local login
    local password
    local password_repeat
    local teacher_name
    local password_hash
    local user_file

    read -r -p "Логин: " login

    if [[ -z "$login" ]]; then
        print_error "Логин не может быть пустым"
        pause
        return
    fi

    if [[ ! "$login" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_error "Логин может содержать только латинские буквы, цифры, _ и -"
        pause
        return
    fi

    user_file="$USERS_DIR/$login.txt"

    if [[ -f "$user_file" ]]; then
        print_error "Пользователь с таким логином уже существует"
        pause
        return
    fi

    read -r -s -p "Пароль: " password
    echo

    if [[ -z "$password" ]]; then
        print_error "Пароль не может быть пустым"
        pause
        return
    fi

    read -r -s -p "Повторите пароль: " password_repeat
    echo

    if [[ "$password" != "$password_repeat" ]]; then
        print_error "Пароли не совпадают"
        pause
        return
    fi

    read -r -p "ФИО преподавателя: " teacher_name

    if [[ -z "$teacher_name" ]]; then
        print_error "ФИО не может быть пустым"
        pause
        return
    fi

    password_hash="$(hash_password "$password")"

    {
        echo "login=$login"
        echo "password_hash=$password_hash"
        echo "teacher_name=$teacher_name"
    } > "$user_file"

    chmod 600 "$user_file"

    mkdir -p "$COURSES_DIR/$login"

    write_log "Зарегистрирован преподаватель: $login"
    print_success "Преподаватель зарегистрирован"
    pause
}

login_teacher() {
    print_header
    echo "=== ВХОД ==="
    echo

    local login
    local password
    local user_file
    local stored_hash
    local password_hash
    local teacher_name

    read -r -p "Логин: " login
    user_file="$USERS_DIR/$login.txt"

    if [[ ! -f "$user_file" ]]; then
        print_error "Пользователь не найден"
        write_log "Неудачная попытка входа: $login"
        pause
        return 1
    fi

    read -r -s -p "Пароль: " password
    echo

    stored_hash="$(grep '^password_hash=' "$user_file" | cut -d'=' -f2-)"
    password_hash="$(hash_password "$password")"

    if [[ "$password_hash" != "$stored_hash" ]]; then
        print_error "Неверный пароль"
        write_log "Неверный пароль для пользователя: $login"
        pause
        return 1
    fi

    teacher_name="$(grep '^teacher_name=' "$user_file" | cut -d'=' -f2-)"

    CURRENT_USER="$login"
    CURRENT_TEACHER="$teacher_name"

    write_log "Вход пользователя: $login"
    return 0
}

list_courses() {
    local user_dir="$COURSES_DIR/$CURRENT_USER"

    echo
    echo "=== КУРСЫ ==="

    mkdir -p "$user_dir"

    local found=0
    local course_dir

    for course_dir in "$user_dir"/*; do
        if [[ -d "$course_dir" ]]; then
            echo "- $(basename "$course_dir")"
            found=1
        fi
    done

    if [[ "$found" -eq 0 ]]; then
        echo "Курсы пока отсутствуют"
    fi

    echo
}

create_course() {
    local course_name
    local course_dir

    read -r -p "Название нового курса: " course_name

    if [[ -z "$course_name" ]]; then
        print_error "Название курса не может быть пустым"
        pause
        return
    fi

    if [[ "$course_name" == *"/"* ]]; then
        print_error "Название курса не должно содержать /"
        pause
        return
    fi

    course_dir="$COURSES_DIR/$CURRENT_USER/$course_name"

    if [[ -d "$course_dir" ]]; then
        print_error "Такой курс уже существует"
        pause
        return
    fi

    mkdir -p "$course_dir/groups"
    printf "%s\n" "$course_name" > "$course_dir/course_name.txt"

    write_log "$CURRENT_USER создал курс: $course_name"
    print_success "Курс создан"
    pause
}

delete_course() {
    list_courses

    local course_name
    local course_dir
    local answer

    read -r -p "Название курса для удаления: " course_name

    course_dir="$COURSES_DIR/$CURRENT_USER/$course_name"

    if [[ ! -d "$course_dir" ]]; then
        print_error "Курс не найден"
        pause
        return
    fi

    read -r -p "Удалить курс '$course_name' и все его данные? (y/n): " answer

    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
        echo "Удаление отменено"
        pause
        return
    fi

    rm -rf -- "$course_dir"

    write_log "$CURRENT_USER удалил курс: $course_name"
    print_success "Курс удалён"
    pause
}

select_course() {
    list_courses

    local course_name
    local course_dir

    read -r -p "Название курса: " course_name

    course_dir="$COURSES_DIR/$CURRENT_USER/$course_name"

    if [[ ! -d "$course_dir" ]]; then
        print_error "Курс не найден"
        pause
        return
    fi

    CURRENT_COURSE="$course_name"
    course_menu
    CURRENT_COURSE=""
}

list_groups() {
    local groups_dir="$COURSES_DIR/$CURRENT_USER/$CURRENT_COURSE/groups"

    echo
    echo "=== ГРУППЫ ==="

    mkdir -p "$groups_dir"

    local found=0
    local group_dir

    for group_dir in "$groups_dir"/*; do
        if [[ -d "$group_dir" ]]; then
            echo "- $(basename "$group_dir")"
            found=1
        fi
    done

    if [[ "$found" -eq 0 ]]; then
        echo "Группы пока отсутствуют"
    fi

    echo
}

create_group() {
    local group_name
    local group_dir

    read -r -p "Название новой группы: " group_name

    if [[ -z "$group_name" ]]; then
        print_error "Название группы не может быть пустым"
        pause
        return
    fi

    if [[ "$group_name" == *"/"* ]]; then
        print_error "Название группы не должно содержать /"
        pause
        return
    fi

    group_dir="$COURSES_DIR/$CURRENT_USER/$CURRENT_COURSE/groups/$group_name"

    if [[ -d "$group_dir" ]]; then
        print_error "Такая группа уже существует"
        pause
        return
    fi

    mkdir -p "$group_dir"

    echo "id,name" > "$group_dir/students.csv"
    echo "student_id,date,grade" > "$group_dir/grades.csv"
    echo "student_id,date,status" > "$group_dir/absences.csv"

    write_log "$CURRENT_USER создал группу '$group_name' в курсе '$CURRENT_COURSE'"
    print_success "Группа создана"
    pause
}

delete_group() {
    list_groups

    local group_name
    local group_dir
    local answer

    read -r -p "Название группы для удаления: " group_name

    group_dir="$COURSES_DIR/$CURRENT_USER/$CURRENT_COURSE/groups/$group_name"

    if [[ ! -d "$group_dir" ]]; then
        print_error "Группа не найдена"
        pause
        return
    fi

    read -r -p "Удалить группу '$group_name' и все её данные? (y/n): " answer

    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
        echo "Удаление отменено"
        pause
        return
    fi

    rm -rf -- "$group_dir"

    write_log "$CURRENT_USER удалил группу '$group_name' из курса '$CURRENT_COURSE'"
    print_success "Группа удалена"
    pause
}

select_group() {
    list_groups

    local group_name
    local group_dir

    read -r -p "Название группы: " group_name

    group_dir="$COURSES_DIR/$CURRENT_USER/$CURRENT_COURSE/groups/$group_name"

    if [[ ! -d "$group_dir" ]]; then
        print_error "Группа не найдена"
        pause
        return
    fi

    CURRENT_GROUP="$group_name"
    group_menu
    CURRENT_GROUP=""
}

get_group_dir() {
    echo "$COURSES_DIR/$CURRENT_USER/$CURRENT_COURSE/groups/$CURRENT_GROUP"
}

student_exists() {
    local students_file="$1"
    local student_id="$2"

    awk -F',' -v id="$student_id" '
        NR > 1 && $1 == id {
            found=1
        }
        END {
            exit !found
        }
    ' "$students_file"
}

add_student() {
    local group_dir
    local students_file
    local student_name
    local student_id

    group_dir="$(get_group_dir)"
    students_file="$group_dir/students.csv"

    read -r -p "ФИО студента: " student_name

    if [[ -z "$student_name" ]]; then
        print_error "ФИО не может быть пустым"
        pause
        return
    fi

    if [[ "$student_name" == *","* ]]; then
        print_error "ФИО не должно содержать запятую"
        pause
        return
    fi

    if tail -n +2 "$students_file" | cut -d',' -f2- | grep -Fxiq "$student_name"; then
        print_error "Студент с таким ФИО уже существует"
        pause
        return
    fi

    student_id="$(date +%s%N)"

    echo "$student_id,$student_name" >> "$students_file"

    write_log "$CURRENT_USER добавил студента '$student_name' в группу '$CURRENT_GROUP'"
    print_success "Студент добавлен. ID: $student_id"
    pause
}

list_students() {
    local group_dir
    local students_file

    group_dir="$(get_group_dir)"
    students_file="$group_dir/students.csv"

    echo
    echo "=== СТУДЕНТЫ ==="

    if [[ ! -f "$students_file" ]] || [[ "$(wc -l < "$students_file")" -le 1 ]]; then
        echo "Студентов пока нет"
        echo
        return
    fi

    awk -F',' 'NR > 1 {print "ID: " $1 " | " $2}' "$students_file"
    echo
}

find_student() {
    local group_dir
    local students_file
    local search

    group_dir="$(get_group_dir)"
    students_file="$group_dir/students.csv"

    read -r -p "Имя или часть имени: " search

    if [[ -z "$search" ]]; then
        print_error "Введите строку для поиска"
        pause
        return
    fi

    echo
    echo "=== РЕЗУЛЬТАТ ПОИСКА ==="

    awk -F',' -v search="$search" '
        BEGIN {
            search=tolower(search)
            found=0
        }
        NR > 1 {
            name=tolower($2)
            if (index(name, search)) {
                print "ID: " $1 " | " $2
                found=1
            }
        }
        END {
            if (!found) {
                print "Студенты не найдены"
            }
        }
    ' "$students_file"

    pause
}

delete_student() {
    local group_dir
    local students_file
    local grades_file
    local absences_file
    local student_id
    local temp_file

    group_dir="$(get_group_dir)"
    students_file="$group_dir/students.csv"
    grades_file="$group_dir/grades.csv"
    absences_file="$group_dir/absences.csv"

    list_students
    read -r -p "ID студента для удаления: " student_id

    if ! student_exists "$students_file" "$student_id"; then
        print_error "Студент не найден"
        pause
        return
    fi

    temp_file="$(mktemp)"
    awk -F',' -v id="$student_id" 'NR == 1 || $1 != id' "$students_file" > "$temp_file"
    mv "$temp_file" "$students_file"

    temp_file="$(mktemp)"
    awk -F',' -v id="$student_id" 'NR == 1 || $1 != id' "$grades_file" > "$temp_file"
    mv "$temp_file" "$grades_file"

    temp_file="$(mktemp)"
    awk -F',' -v id="$student_id" 'NR == 1 || $1 != id' "$absences_file" > "$temp_file"
    mv "$temp_file" "$absences_file"

    write_log "$CURRENT_USER удалил студента ID=$student_id из группы '$CURRENT_GROUP'"
    print_success "Студент и связанные данные удалены"
    pause
}

set_grade() {
    local group_dir
    local students_file
    local grades_file
    local student_id
    local lesson_date
    local grade

    group_dir="$(get_group_dir)"
    students_file="$group_dir/students.csv"
    grades_file="$group_dir/grades.csv"

    list_students
    read -r -p "ID студента: " student_id

    if ! student_exists "$students_file" "$student_id"; then
        print_error "Студент не найден"
        pause
        return
    fi

    read -r -p "Дата (YYYY-MM-DD): " lesson_date

    if ! valid_date "$lesson_date"; then
        print_error "Некорректная дата"
        pause
        return
    fi

    read -r -p "Оценка (2-5): " grade

    if [[ ! "$grade" =~ ^[2-5]$ ]]; then
        print_error "Оценка должна быть от 2 до 5"
        pause
        return
    fi

    echo "$student_id,$lesson_date,$grade" >> "$grades_file"

    write_log "$CURRENT_USER поставил оценку $grade студенту ID=$student_id"
    print_success "Оценка сохранена"
    pause
}

show_grades() {
    local group_dir
    local students_file
    local grades_file

    group_dir="$(get_group_dir)"
    students_file="$group_dir/students.csv"
    grades_file="$group_dir/grades.csv"

    echo
    echo "=== ОЦЕНКИ ==="

    if [[ "$(wc -l < "$grades_file")" -le 1 ]]; then
        echo "Оценок пока нет"
        echo
        return
    fi

    awk -F',' '
        NR == FNR {
            if (FNR > 1) {
                names[$1]=$2
            }
            next
        }
        FNR > 1 {
            print names[$1] " | " $2 " | Оценка: " $3
        }
    ' "$students_file" "$grades_file"

    echo
}

delete_grade() {
    local group_dir
    local grades_file
    local student_id
    local lesson_date
    local temp_file
    local before
    local after

    group_dir="$(get_group_dir)"
    grades_file="$group_dir/grades.csv"

    show_grades

    read -r -p "ID студента: " student_id
    read -r -p "Дата оценки (YYYY-MM-DD): " lesson_date

    temp_file="$(mktemp)"
    before="$(wc -l < "$grades_file")"

    awk -F',' -v id="$student_id" -v d="$lesson_date" '
        NR == 1 || !($1 == id && $2 == d)
    ' "$grades_file" > "$temp_file"

    mv "$temp_file" "$grades_file"

    after="$(wc -l < "$grades_file")"

    if [[ "$before" -eq "$after" ]]; then
        print_error "Оценка не найдена"
    else
        write_log "$CURRENT_USER удалил оценку студенту ID=$student_id за $lesson_date"
        print_success "Оценка удалена"
    fi

    pause
}

set_absence() {
    local group_dir
    local students_file
    local absences_file
    local student_id
    local lesson_date

    group_dir="$(get_group_dir)"
    students_file="$group_dir/students.csv"
    absences_file="$group_dir/absences.csv"

    list_students
    read -r -p "ID студента: " student_id

    if ! student_exists "$students_file" "$student_id"; then
        print_error "Студент не найден"
        pause
        return
    fi

    read -r -p "Дата пропуска (YYYY-MM-DD): " lesson_date

    if ! valid_date "$lesson_date"; then
        print_error "Некорректная дата"
        pause
        return
    fi

    echo "$student_id,$lesson_date,нб" >> "$absences_file"

    write_log "$CURRENT_USER отметил пропуск студенту ID=$student_id"
    print_success "Пропуск сохранён"
    pause
}

show_absences() {
    local group_dir
    local students_file
    local absences_file

    group_dir="$(get_group_dir)"
    students_file="$group_dir/students.csv"
    absences_file="$group_dir/absences.csv"

    echo
    echo "=== ПРОПУСКИ ==="

    if [[ "$(wc -l < "$absences_file")" -le 1 ]]; then
        echo "Пропусков пока нет"
        echo
        return
    fi

    awk -F',' '
        NR == FNR {
            if (FNR > 1) {
                names[$1]=$2
            }
            next
        }
        FNR > 1 {
            print names[$1] " | " $2 " | " $3
        }
    ' "$students_file" "$absences_file"

    echo
}

delete_absence() {
    local group_dir
    local absences_file
    local student_id
    local lesson_date
    local temp_file
    local before
    local after

    group_dir="$(get_group_dir)"
    absences_file="$group_dir/absences.csv"

    show_absences

    read -r -p "ID студента: " student_id
    read -r -p "Дата пропуска (YYYY-MM-DD): " lesson_date

    temp_file="$(mktemp)"
    before="$(wc -l < "$absences_file")"

    awk -F',' -v id="$student_id" -v d="$lesson_date" '
        NR == 1 || !($1 == id && $2 == d)
    ' "$absences_file" > "$temp_file"

    mv "$temp_file" "$absences_file"

    after="$(wc -l < "$absences_file")"

    if [[ "$before" -eq "$after" ]]; then
        print_error "Пропуск не найден"
    else
        write_log "$CURRENT_USER удалил пропуск студенту ID=$student_id за $lesson_date"
        print_success "Пропуск удалён"
    fi

    pause
}

filter_by_grade() {
    local group_dir
    local students_file
    local grades_file
    local grade

    group_dir="$(get_group_dir)"
    students_file="$group_dir/students.csv"
    grades_file="$group_dir/grades.csv"

    read -r -p "Оценка для выборки (2-5): " grade

    if [[ ! "$grade" =~ ^[2-5]$ ]]; then
        print_error "Оценка должна быть от 2 до 5"
        pause
        return
    fi

    echo
    echo "=== СТУДЕНТЫ С ОЦЕНКОЙ $grade ==="

    awk -F',' -v grade="$grade" '
        NR == FNR {
            if (FNR > 1) {
                names[$1]=$2
            }
            next
        }
        FNR > 1 && $3 == grade {
            print names[$1] " | " $2 " | Оценка: " $3
            found=1
        }
        END {
            if (!found) {
                print "Записи не найдены"
            }
        }
    ' "$students_file" "$grades_file"

    pause
}

filter_by_name() {
    find_student
}

export_csv() {
    local group_dir
    local export_dir

    group_dir="$(get_group_dir)"

    export_dir="$EXPORTS_DIR/${CURRENT_USER}_${CURRENT_COURSE}_${CURRENT_GROUP}_$(date '+%Y%m%d_%H%M%S')"

    mkdir -p "$export_dir"

    cp "$group_dir/students.csv" "$export_dir/"
    cp "$group_dir/grades.csv" "$export_dir/"
    cp "$group_dir/absences.csv" "$export_dir/"

    write_log "$CURRENT_USER экспортировал группу '$CURRENT_GROUP'"
    print_success "Данные экспортированы в: $export_dir"
    pause
}

validate_students_csv() {
    local source_file="$1"
    local header

    if [[ ! -f "$source_file" ]]; then
        return 1
    fi

    header="$(head -n 1 "$source_file" | tr -d '\r')"

    [[ "$header" == "id,name" ]]
}

import_students_csv() {
    local group_dir
    local source_file

    group_dir="$(get_group_dir)"

    read -r -p "Путь к CSV-файлу студентов: " source_file

    if [[ ! -f "$source_file" ]]; then
        print_error "Файл не найден"
        pause
        return
    fi

    if ! validate_students_csv "$source_file"; then
        print_error "Некорректный CSV. Первая строка должна быть: id,name"
        pause
        return
    fi

    cp "$source_file" "$group_dir/students.csv"

    write_log "$CURRENT_USER импортировал студентов в группу '$CURRENT_GROUP'"
    print_success "CSV импортирован"
    pause
}

backup_data() {
    local backup_file

    backup_file="$BACKUPS_DIR/journal_backup_$(date '+%Y%m%d_%H%M%S').tar.gz"

    tar -czf "$backup_file" -C "$BASE_DIR" data

    write_log "Создана резервная копия: $backup_file"
    echo "Резервная копия создана:"
    echo "$backup_file"
}

group_menu() {
    local choice

    while true; do
        print_header
        echo "Преподаватель: $CURRENT_TEACHER"
        echo "Курс: $CURRENT_COURSE"
        echo "Группа: $CURRENT_GROUP"
        echo
        echo "1. Показать студентов"
        echo "2. Добавить студента"
        echo "3. Найти студента"
        echo "4. Удалить студента"
        echo "5. Поставить оценку"
        echo "6. Показать оценки"
        echo "7. Удалить оценку"
        echo "8. Отметить пропуск"
        echo "9. Показать пропуски"
        echo "10. Удалить пропуск"
        echo "11. Выборка по оценке"
        echo "12. Выборка по имени"
        echo "13. Экспорт CSV"
        echo "14. Импорт студентов из CSV"
        echo "0. Назад"
        echo

        read -r -p "Выберите действие: " choice

        case "$choice" in
            1)
                print_header
                list_students
                pause
                ;;
            2) add_student ;;
            3) find_student ;;
            4) delete_student ;;
            5) set_grade ;;
            6)
                print_header
                show_grades
                pause
                ;;
            7) delete_grade ;;
            8) set_absence ;;
            9)
                print_header
                show_absences
                pause
                ;;
            10) delete_absence ;;
            11) filter_by_grade ;;
            12) filter_by_name ;;
            13) export_csv ;;
            14) import_students_csv ;;
            0) return ;;
            *)
                print_error "Неизвестный пункт меню"
                pause
                ;;
        esac
    done
}

course_menu() {
    local choice

    while true; do
        print_header
        echo "Преподаватель: $CURRENT_TEACHER"
        echo "Курс: $CURRENT_COURSE"
        echo
        echo "1. Показать группы"
        echo "2. Создать группу"
        echo "3. Войти в группу"
        echo "4. Удалить группу"
        echo "0. Назад"
        echo

        read -r -p "Выберите действие: " choice

        case "$choice" in
            1)
                print_header
                list_groups
                pause
                ;;
            2) create_group ;;
            3) select_group ;;
            4) delete_group ;;
            0) return ;;
            *)
                print_error "Неизвестный пункт меню"
                pause
                ;;
        esac
    done
}

courses_menu() {
    local choice

    while true; do
        print_header
        echo "Преподаватель: $CURRENT_TEACHER"
        echo "Логин: $CURRENT_USER"
        echo
        echo "1. Показать курсы"
        echo "2. Создать курс"
        echo "3. Войти в курс"
        echo "4. Удалить курс"
        echo "5. Создать резервную копию"
        echo "0. Выйти из аккаунта"
        echo

        read -r -p "Выберите действие: " choice

        case "$choice" in
            1)
                print_header
                list_courses
                pause
                ;;
            2) create_course ;;
            3) select_course ;;
            4) delete_course ;;
            5)
                backup_data
                pause
                ;;
            0)
                write_log "Выход пользователя: $CURRENT_USER"
                CURRENT_USER=""
                CURRENT_TEACHER=""
                CURRENT_COURSE=""
                CURRENT_GROUP=""
                return
                ;;
            *)
                print_error "Неизвестный пункт меню"
                pause
                ;;
        esac
    done
}

interactive_mode() {
    local choice

    while true; do
        print_header
        echo "1. Войти"
        echo "2. Создать аккаунт преподавателя"
        echo "0. Выход"
        echo

        read -r -p "Выберите действие: " choice

        case "$choice" in
            1)
                if login_teacher; then
                    courses_menu
                fi
                ;;
            2) register_teacher ;;
            0)
                echo "Работа завершена"
                exit 0
                ;;
            *)
                print_error "Неизвестный пункт меню"
                pause
                ;;
        esac
    done
}

show_help() {
    cat <<'EOF'
Электронный журнал

Использование:
  ./journal.sh
  ./journal.sh --help
  ./journal.sh --version
  ./journal.sh --backup

Командный режим:
  ./journal.sh --list-students USER COURSE GROUP
  ./journal.sh --find-student USER COURSE GROUP NAME
  ./journal.sh --add-student USER COURSE GROUP NAME
  ./journal.sh --set-grade USER COURSE GROUP STUDENT_ID GRADE DATE
  ./journal.sh --set-absence USER COURSE GROUP STUDENT_ID DATE
  ./journal.sh --export USER COURSE GROUP

Примеры:
  ./journal.sh --list-students roma "Dangen master" DGB-26
  ./journal.sh --find-student roma "Dangen master" DGB-26 Иванов
  ./journal.sh --add-student roma "Dangen master" DGB-26 "Сидоров Сидор Сидорович"
EOF
}

show_version() {
    echo "Electronic Journal $VERSION"
}

cli_group_dir() {
    local user="$1"
    local course="$2"
    local group="$3"

    echo "$COURSES_DIR/$user/$course/groups/$group"
}

cli_group_exists() {
    local group_dir

    group_dir="$(cli_group_dir "$1" "$2" "$3")"
    [[ -d "$group_dir" ]]
}

cli_list_students() {
    local user="$1"
    local course="$2"
    local group="$3"
    local group_dir
    local students_file

    group_dir="$(cli_group_dir "$user" "$course" "$group")"

    if [[ ! -d "$group_dir" ]]; then
        echo "Ошибка: группа не найдена"
        return 1
    fi

    students_file="$group_dir/students.csv"

    if [[ ! -f "$students_file" ]]; then
        echo "Ошибка: students.csv не найден"
        return 1
    fi

    awk -F',' 'NR > 1 {print "ID: " $1 " | " $2}' "$students_file"
}

cli_find_student() {
    local user="$1"
    local course="$2"
    local group="$3"
    local search="$4"
    local group_dir
    local students_file

    group_dir="$(cli_group_dir "$user" "$course" "$group")"

    if [[ ! -d "$group_dir" ]]; then
        echo "Ошибка: группа не найдена"
        return 1
    fi

    students_file="$group_dir/students.csv"

    awk -F',' -v search="$search" '
        BEGIN {
            search=tolower(search)
            found=0
        }
        NR > 1 {
            name=tolower($2)
            if (index(name, search)) {
                print "ID: " $1 " | " $2
                found=1
            }
        }
        END {
            if (!found) {
                print "Студенты не найдены"
            }
        }
    ' "$students_file"
}

cli_add_student() {
    local user="$1"
    local course="$2"
    local group="$3"
    local student_name="$4"
    local group_dir
    local students_file
    local student_id

    group_dir="$(cli_group_dir "$user" "$course" "$group")"

    if [[ ! -d "$group_dir" ]]; then
        echo "Ошибка: группа не найдена"
        return 1
    fi

    if [[ -z "$student_name" || "$student_name" == *","* ]]; then
        echo "Ошибка: некорректное ФИО"
        return 1
    fi

    students_file="$group_dir/students.csv"

    if tail -n +2 "$students_file" | cut -d',' -f2- | grep -Fxiq "$student_name"; then
        echo "Ошибка: студент уже существует"
        return 1
    fi

    student_id="$(date +%s%N)"
    echo "$student_id,$student_name" >> "$students_file"

    write_log "$user добавил студента '$student_name' через CLI"

    echo "Студент добавлен"
    echo "ID: $student_id"
}

cli_set_grade() {
    local user="$1"
    local course="$2"
    local group="$3"
    local student_id="$4"
    local grade="$5"
    local lesson_date="$6"
    local group_dir
    local students_file
    local grades_file

    group_dir="$(cli_group_dir "$user" "$course" "$group")"

    if [[ ! -d "$group_dir" ]]; then
        echo "Ошибка: группа не найдена"
        return 1
    fi

    students_file="$group_dir/students.csv"
    grades_file="$group_dir/grades.csv"

    if ! student_exists "$students_file" "$student_id"; then
        echo "Ошибка: студент не найден"
        return 1
    fi

    if [[ ! "$grade" =~ ^[2-5]$ ]]; then
        echo "Ошибка: оценка должна быть от 2 до 5"
        return 1
    fi

    if ! valid_date "$lesson_date"; then
        echo "Ошибка: некорректная дата"
        return 1
    fi

    echo "$student_id,$lesson_date,$grade" >> "$grades_file"

    write_log "$user поставил оценку $grade студенту ID=$student_id через CLI"
    echo "Оценка сохранена"
}

cli_set_absence() {
    local user="$1"
    local course="$2"
    local group="$3"
    local student_id="$4"
    local lesson_date="$5"
    local group_dir
    local students_file
    local absences_file

    group_dir="$(cli_group_dir "$user" "$course" "$group")"

    if [[ ! -d "$group_dir" ]]; then
        echo "Ошибка: группа не найдена"
        return 1
    fi

    students_file="$group_dir/students.csv"
    absences_file="$group_dir/absences.csv"

    if ! student_exists "$students_file" "$student_id"; then
        echo "Ошибка: студент не найден"
        return 1
    fi

    if ! valid_date "$lesson_date"; then
        echo "Ошибка: некорректная дата"
        return 1
    fi

    echo "$student_id,$lesson_date,нб" >> "$absences_file"

    write_log "$user отметил пропуск студенту ID=$student_id через CLI"
    echo "Пропуск сохранён"
}

cli_export() {
    local user="$1"
    local course="$2"
    local group="$3"
    local group_dir
    local export_dir

    group_dir="$(cli_group_dir "$user" "$course" "$group")"

    if [[ ! -d "$group_dir" ]]; then
        echo "Ошибка: группа не найдена"
        return 1
    fi

    export_dir="$EXPORTS_DIR/${user}_${course}_${group}_$(date '+%Y%m%d_%H%M%S')"

    mkdir -p "$export_dir"

    cp "$group_dir/students.csv" "$export_dir/"
    cp "$group_dir/grades.csv" "$export_dir/"
    cp "$group_dir/absences.csv" "$export_dir/"

    write_log "$user экспортировал группу '$group' через CLI"

    echo "Экспорт завершён:"
    echo "$export_dir"
}

command_line_mode() {
    local command="$1"

    case "$command" in
        --help|-h)
            show_help
            ;;

        --version|-v)
            show_version
            ;;

        --backup)
            backup_data
            ;;

        --list-students)
            if [[ "$#" -ne 4 ]]; then
                echo "Использование:"
                echo "./journal.sh --list-students USER COURSE GROUP"
                return 1
            fi

            cli_list_students "$2" "$3" "$4"
            ;;

        --find-student)
            if [[ "$#" -ne 5 ]]; then
                echo "Использование:"
                echo "./journal.sh --find-student USER COURSE GROUP NAME"
                return 1
            fi

            cli_find_student "$2" "$3" "$4" "$5"
            ;;

        --add-student)
            if [[ "$#" -ne 5 ]]; then
                echo "Использование:"
                echo "./journal.sh --add-student USER COURSE GROUP NAME"
                return 1
            fi

            cli_add_student "$2" "$3" "$4" "$5"
            ;;

        --set-grade)
            if [[ "$#" -ne 7 ]]; then
                echo "Использование:"
                echo "./journal.sh --set-grade USER COURSE GROUP STUDENT_ID GRADE DATE"
                return 1
            fi

            cli_set_grade "$2" "$3" "$4" "$5" "$6" "$7"
            ;;

        --set-absence)
            if [[ "$#" -ne 6 ]]; then
                echo "Использование:"
                echo "./journal.sh --set-absence USER COURSE GROUP STUDENT_ID DATE"
                return 1
            fi

            cli_set_absence "$2" "$3" "$4" "$5" "$6"
            ;;

        --export)
            if [[ "$#" -ne 4 ]]; then
                echo "Использование:"
                echo "./journal.sh --export USER COURSE GROUP"
                return 1
            fi

            cli_export "$2" "$3" "$4"
            ;;

        *)
            echo "Неизвестная команда: $command"
            echo "Используйте ./journal.sh --help"
            return 1
            ;;
    esac
}

main() {
    init_project

    if [[ "$#" -eq 0 ]]; then
        interactive_mode
    else
        command_line_mode "$@"
    fi
}

main "$@"
