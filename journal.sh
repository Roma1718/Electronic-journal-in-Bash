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

# Функция: print_header
# Назначение: Очищает терминал и печатает заголовок журнала.
# Входные данные: Нет.
# Результат: Заголовок в stdout; явного return нет.
# Ошибки и сигнализация: Если clear недоступен, терминал может не очиститься; ошибка не обрабатывается.
print_header() {
    clear
    echo "=========================================="
    echo "          ЭЛЕКТРОННЫЙ ЖУРНАЛ"
    echo "=========================================="
}

# Функция: print_error
# Назначение: Показывает сообщение об ошибке.
# Входные данные: $1 — текст сообщения.
# Результат: Печатает «ОШИБКА: ...» в stdout, с пустыми строками по краям.
# Ошибки и сигнализация: Не выставляет код ошибки 1: сообщение само по себе не меняет статус операции.
print_error() {
    echo
    echo "ОШИБКА: $1"
    echo
}

# Функция: print_success
# Назначение: Показывает уведомление об успешном действии.
# Входные данные: $1 — текст сообщения.
# Результат: Печатает «УСПЕШНО: ...» в stdout.
# Ошибки и сигнализация: Ошибки вывода отдельно не проверяются.
print_success() {
    echo
    echo "УСПЕШНО: $1"
    echo
}

# Функция: pause
# Назначение: Приостанавливает экран до нажатия Enter.
# Входные данные: Нет; читает одну строку из stdin.
# Результат: Запрос на нажатие Enter; отдельного значения не возвращает.
# Ошибки и сигнализация: При закрытом stdin read завершается с ошибкой; обработки нет.
pause() {
    echo
    read -r -p "Нажмите Enter для продолжения..."
}

# Функция: write_log
# Назначение: Добавляет запись с текущим временем в журнал событий.
# Входные данные: $1 — описание события.
# Результат: Дописывает строку в logs/journal.log; stdout пуст.
# Ошибки и сигнализация: Если файл недоступен для записи, shell сообщает об ошибке перенаправления; вызывающий код обычно не проверяет статус.
write_log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $message" >> "$LOG_FILE"
}

# Функция: init_project
# Назначение: Создаёт рабочие каталоги и файл журнала.
# Входные данные: Нет; использует глобальные пути *_DIR и LOG_FILE.
# Результат: Создаёт недостающие папки и пустой файл журнала.
# Ошибки и сигнализация: Ошибки mkdir/touch при недостатке прав или места не проверяются; возвращается статус последней команды touch.
init_project() {
    mkdir -p "$USERS_DIR"
    mkdir -p "$COURSES_DIR"
    mkdir -p "$EXPORTS_DIR"
    mkdir -p "$BACKUPS_DIR"
    mkdir -p "$LOGS_DIR"
    touch "$LOG_FILE"
}

# Функция: hash_password
# Назначение: Вычисляет SHA-256 от переданного пароля.
# Входные данные: $1 — пароль как строка.
# Результат: Печатает 64-символьную шестнадцатеричную сумму SHA-256 в stdout.
# Ошибки и сигнализация: При отсутствии sha256sum/awk возможен сбой; ошибки конвейера без pipefail могут не отражаться в итоговом статусе.
hash_password() {
    local password="$1"
    printf "%s" "$password" | sha256sum | awk '{print $1}'
}

# Функция: valid_date
# Назначение: Проверяет формат и календарную корректность даты.
# Входные данные: $1 — дата в формате YYYY-MM-DD.
# Результат: Ничего не печатает; статус 0 — дата принята, 1 — отклонена.
# Ошибки и сигнализация: Некорректная форма или невозможность разобрать дату приводит к ненулевому статусу; stderr команды date подавлен.
valid_date() {
    local input_date="$1"

    if [[ ! "$input_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        return 1
    fi

    date -d "$input_date" "+%Y-%m-%d" >/dev/null 2>&1
}

# Функция: register_teacher
# Назначение: Регистрирует преподавателя, создаёт файл профиля и его каталог курсов.
# Входные данные: Интерактивно: логин, пароль дважды, ФИО; аргументов нет.
# Результат: Создаёт users/<login>.txt с SHA-256 пароля, выставляет chmod 600; пишет событие в журнал.
# Ошибки и сигнализация: Пустой/недопустимый или занятый логин, пустой пароль/ФИО, разные пароли: print_error и возврат в меню; статус 1 явно не задан. Ошибки диска/прав не контролируются.
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

# Функция: login_teacher
# Назначение: Проверяет учётные данные преподавателя и открывает сеанс.
# Входные данные: Интерактивно: логин и скрыто вводимый пароль.
# Результат: Устанавливает CURRENT_USER и CURRENT_TEACHER; статус 0 при успешном входе.
# Ошибки и сигнализация: Отсутствует профиль или пароль неверен: сообщение, запись в журнал и return 1. Ошибки чтения файла отдельно не проверяются.
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

# Функция: list_courses
# Назначение: Показывает курсы текущего преподавателя.
# Входные данные: Глобальная переменная CURRENT_USER.
# Результат: Выводит названия папок курсов либо сообщение об их отсутствии.
# Ошибки и сигнализация: Неудача mkdir/чтения каталога специально не диагностируется.
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

# Функция: create_course
# Назначение: Создаёт каталог нового курса и файл с его названием.
# Входные данные: Интерактивно: название курса; использует CURRENT_USER.
# Результат: Создаёт courses/<user>/<course>/groups и course_name.txt, пишет лог.
# Ошибки и сигнализация: Пустое название, символ / или уже существующий курс: print_error и выход; явный статус ошибки не установлен. Ошибки записи не контролируются.
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

# Функция: delete_course
# Назначение: Удаляет выбранный курс вместе с его данными.
# Входные данные: Интерактивно: название курса и подтверждение y/Y.
# Результат: После подтверждения удаляет каталог рекурсивно, пишет запись в журнал.
# Ошибки и сигнализация: Курс отсутствует или пользователь отменил удаление: сообщение и выход; ошибки rm не проверяются, поэтому возможен ложный вывод об успехе.
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

# Функция: select_course
# Назначение: Открывает меню указанного курса.
# Входные данные: Интерактивно: название; глобальные CURRENT_USER и CURRENT_COURSE.
# Результат: Запоминает курс, вызывает course_menu и затем очищает CURRENT_COURSE.
# Ошибки и сигнализация: Несуществующий курс: print_error и выход без явного return 1.
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

# Функция: list_groups
# Назначение: Показывает группы текущего курса.
# Входные данные: Глобальные CURRENT_USER и CURRENT_COURSE.
# Результат: Выводит названия каталогов групп или сообщение об отсутствии.
# Ошибки и сигнализация: Ошибки создания/чтения каталога групп не обрабатываются.
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

# Функция: create_group
# Назначение: Создаёт группу и три CSV-файла с заголовками.
# Входные данные: Интерактивно: название группы; глобальный текущий курс.
# Результат: Создаёт students.csv, grades.csv, absences.csv, фиксирует событие.
# Ошибки и сигнализация: Пустое название, / или существующая группа: сообщение и выход; сбой mkdir/записи CSV отдельно не обрабатывается.
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

# Функция: delete_group
# Назначение: Удаляет группу со студентами, оценками и пропусками.
# Входные данные: Интерактивно: название группы и подтверждение y/Y.
# Результат: Рекурсивно удаляет каталог группы; выводит результат и пишет лог.
# Ошибки и сигнализация: Группа не существует или подтверждение не получено: сообщение и выход; ошибки rm не проверяются.
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

# Функция: select_group
# Назначение: Открывает меню выбранной группы.
# Входные данные: Интерактивно: название группы; глобальные переменные текущего курса.
# Результат: Устанавливает CURRENT_GROUP, вызывает group_menu и затем сбрасывает выбор.
# Ошибки и сигнализация: Если каталог группы не найден, показывает ошибку и завершает функцию без явного ненулевого статуса.
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

# Функция: get_group_dir
# Назначение: Формирует путь к каталогу выбранной группы.
# Входные данные: Глобальные CURRENT_USER, CURRENT_COURSE и CURRENT_GROUP.
# Результат: Печатает полный путь в stdout; используется через подстановку $(...).
# Ошибки и сигнализация: Существование каталога и корректность глобальных значений не проверяются.
get_group_dir() {
    echo "$COURSES_DIR/$CURRENT_USER/$CURRENT_COURSE/groups/$CURRENT_GROUP"
}

# Функция: student_exists
# Назначение: Ищет студента с указанным ID в CSV.
# Входные данные: $1 — путь students.csv; $2 — ID студента.
# Результат: Ничего не печатает; код 0 при совпадении ID, 1 при отсутствии.
# Ошибки и сигнализация: Отсутствующий/нечитаемый CSV вызывает диагностику awk в stderr; код также ненулевой.
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

# Функция: add_student
# Назначение: Добавляет студента в выбранную группу.
# Входные данные: Интерактивно: ФИО; текущая группа задаётся глобальными переменными.
# Результат: Генерирует ID по date +%s%N и дописывает строку в students.csv.
# Ошибки и сигнализация: Пустое ФИО, запятая или совпадающее ФИО: print_error и выход без явного return 1. Сбои записи не проверяются.
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

# Функция: list_students
# Назначение: Показывает список студентов и их идентификаторов.
# Входные данные: Текущая группа из глобальных переменных.
# Результат: Читает students.csv и печатает строки ID и ФИО.
# Ошибки и сигнализация: Нет файла или только заголовок: «Студентов пока нет»; ошибки awk отдельно не обработаны.
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

# Функция: find_student
# Назначение: Ищет студентов по подстроке ФИО без учёта регистра.
# Входные данные: Интерактивно: часть имени; текущая группа.
# Результат: Печатает совпадения с ID либо «Студенты не найдены».
# Ошибки и сигнализация: Пустой запрос: print_error и выход; ошибки чтения CSV могут появиться в stderr.
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

# Функция: delete_student
# Назначение: Удаляет студента и его связанные оценки/пропуски.
# Входные данные: Интерактивно: ID; файлы students.csv, grades.csv, absences.csv.
# Результат: Переписывает три CSV через временные файлы mktemp и mv.
# Ошибки и сигнализация: Неизвестный ID: сообщение и выход. Сбои mktemp/awk/mv не контролируются; частичная модификация возможна.
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

# Функция: set_grade
# Назначение: Добавляет оценку студенту на указанную дату.
# Входные данные: Интерактивно: ID, дата YYYY-MM-DD, оценка от 2 до 5.
# Результат: Дописывает запись в grades.csv и журнал событий.
# Ошибки и сигнализация: Неизвестный ID, неверная дата или оценка: print_error и выход без явного кода 1; ошибка записи CSV отдельно не проверяется.
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

# Функция: show_grades
# Назначение: Отображает оценки с ФИО студентов и датами.
# Входные данные: Текущая группа и CSV-файлы students.csv/grades.csv.
# Результат: Соединяет данные двух CSV через awk и печатает таблицу строк.
# Ошибки и сигнализация: Если оценок нет, выводит информационное сообщение; отсутствие/повреждение файлов отдельно не проверяется.
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

# Функция: delete_grade
# Назначение: Удаляет оценки студента за заданную дату.
# Входные данные: Интерактивно: ID и дата оценки.
# Результат: Фильтрует grades.csv во временный файл, заменяет исходный; может удалить несколько строк с тем же ID и датой.
# Ошибки и сигнализация: Если число строк не изменилось, пишет «Оценка не найдена». Ошибки mktemp/awk/mv не проверяются; статус 1 не задаётся.
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

# Функция: set_absence
# Назначение: Отмечает пропуск занятия студентом.
# Входные данные: Интерактивно: ID и дата YYYY-MM-DD.
# Результат: Дописывает в absences.csv запись с кодом «нб».
# Ошибки и сигнализация: Неизвестный ID или неверная дата: сообщение и выход; сбой записи не проверяется.
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

# Функция: show_absences
# Назначение: Показывает даты и статусы пропусков студентов.
# Входные данные: Текущая группа и её students.csv/absences.csv.
# Результат: Объединяет CSV по ID через awk и выводит записи.
# Ошибки и сигнализация: Пустой журнал пропусков: информационное сообщение; ошибки чтения отдельно не обрабатываются.
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

# Функция: delete_absence
# Назначение: Удаляет пропуски студента за выбранную дату.
# Входные данные: Интерактивно: ID и дата пропуска.
# Результат: Фильтрует absences.csv, сохраняя строки иных дат и студентов.
# Ошибки и сигнализация: Если ни одна запись не удалена: «Пропуск не найден». Ошибки временных файлов и записи не контролируются.
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

# Функция: filter_by_grade
# Назначение: Выбирает студентов с заданной оценкой.
# Входные данные: Интерактивно: оценка 2–5; текущая группа.
# Результат: Выводит все подходящие записи с датами и ФИО.
# Ошибки и сигнализация: Некорректная оценка: сообщение и выход; если совпадений нет, «Записи не найдены». Ошибки чтения не проверяются.
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

# Функция: filter_by_name
# Назначение: Передаёт управление поиску студента по имени.
# Входные данные: Ввод и проверка выполняются в find_student.
# Результат: Вывод совпадений через find_student; собственных данных не создаёт.
# Ошибки и сигнализация: Ошибки и сообщения совпадают с find_student.
filter_by_name() {
    find_student
}

# Функция: export_csv
# Назначение: Экспортирует файлы выбранной группы в отдельную папку.
# Входные данные: Текущие пользователь, курс, группа и EXPORTS_DIR.
# Результат: Создаёт каталог с временной меткой; копирует три CSV.
# Ошибки и сигнализация: Сбои mkdir/cp не проверяются, функция может напечатать успех при неполном экспорте.
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

# Функция: validate_students_csv
# Назначение: Проверяет наличие файла и точный заголовок таблицы студентов.
# Входные данные: $1 — путь к CSV.
# Результат: Статус 0, если первая строка после удаления CR равна id,name; иначе 1.
# Ошибки и сигнализация: Отсутствие файла возвращает 1; содержимое остальных строк не проверяется.
validate_students_csv() {
    local source_file="$1"
    local header

    if [[ ! -f "$source_file" ]]; then
        return 1
    fi

    header="$(head -n 1 "$source_file" | tr -d '\r')"

    [[ "$header" == "id,name" ]]
}

# Функция: import_students_csv
# Назначение: Заменяет список студентов CSV-файлом из указанного пути.
# Входные данные: Интерактивно: путь к CSV; выбранная группа.
# Результат: После проверки заголовка копирует файл как students.csv.
# Ошибки и сигнализация: Файл не найден или заголовок неверен: print_error и выход; сбой cp не контролируется. Согласованность с оценками/пропусками не проверяется.
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

# Функция: backup_data
# Назначение: Архивирует каталог data в резервную копию tar.gz.
# Входные данные: Глобальные BASE_DIR и BACKUPS_DIR; аргументов нет.
# Результат: Создаёт архив с временной меткой, пишет лог и печатает путь.
# Ошибки и сигнализация: Ошибка tar не проверяется, поэтому сообщение о создании может появиться при сбое.
backup_data() {
    local backup_file

    backup_file="$BACKUPS_DIR/journal_backup_$(date '+%Y%m%d_%H%M%S').tar.gz"

    tar -czf "$backup_file" -C "$BASE_DIR" data

    write_log "Создана резервная копия: $backup_file"
    echo "Резервная копия создана:"
    echo "$backup_file"
}

# Функция: group_menu
# Назначение: Запускает цикл меню операций со студентами и оценками.
# Входные данные: Интерактивный выбор пункта; текущая группа.
# Результат: Вызывает нужную функцию; пункт 0 возвращает к меню курса.
# Ошибки и сигнализация: Неизвестный пункт: print_error и повтор меню; ошибки вложенных функций не собираются.
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

# Функция: course_menu
# Назначение: Запускает цикл меню групп текущего курса.
# Входные данные: Интерактивный выбор пункта; текущий курс.
# Результат: Показывает группы/создаёт/выбирает/удаляет; пункт 0 возвращает назад.
# Ошибки и сигнализация: Неизвестный пункт: сообщение об ошибке и повтор ввода.
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

# Функция: courses_menu
# Назначение: Запускает цикл меню курсов авторизованного преподавателя.
# Входные данные: Интерактивный выбор; CURRENT_USER/CURRENT_TEACHER.
# Результат: Позволяет управлять курсами и резервным копированием; при выходе сбрасывает состояние сеанса.
# Ошибки и сигнализация: Неизвестный пункт выводит ошибку; ошибки операций меню отдельно не обрабатываются.
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

# Функция: interactive_mode
# Назначение: Запускает главное меню регистрации, входа и выхода.
# Входные данные: Интерактивный выбор пункта из stdin.
# Результат: После входа открывает courses_menu; по пункту 0 вызывает exit 0.
# Ошибки и сигнализация: Неверный пункт: сообщение и повтор; вход с ошибкой определяется статусом login_teacher.
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

# Функция: show_help
# Назначение: Печатает справку по параметрам командной строки.
# Входные данные: Нет.
# Результат: Выводит список поддерживаемых опций и примеры вызова.
# Ошибки и сигнализация: Отдельная обработка ошибок вывода отсутствует.
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

# Функция: show_version
# Назначение: Печатает версию программы.
# Входные данные: Глобальная VERSION.
# Результат: Строка Electronic Journal <version> в stdout.
# Ошибки и сигнализация: Ошибки вывода не обрабатываются.
show_version() {
    echo "Electronic Journal $VERSION"
}

# Функция: cli_group_dir
# Назначение: Составляет путь к группе по аргументам командной строки.
# Входные данные: $1 — пользователь, $2 — курс, $3 — группа.
# Результат: Печатает путь в stdout; наличие папки не проверяет.
# Ошибки и сигнализация: Ошибки ввода/опасные компоненты пути не валидируются.
cli_group_dir() {
    local user="$1"
    local course="$2"
    local group="$3"

    echo "$COURSES_DIR/$user/$course/groups/$group"
}

# Функция: cli_group_exists
# Назначение: Проверяет наличие каталога группы.
# Входные данные: $1 — пользователь, $2 — курс, $3 — группа.
# Результат: Статус 0, если каталог существует; 1 — если отсутствует.
# Ошибки и сигнализация: Сообщений не печатает; ошибка представлена кодом проверки [[ -d ... ]].
cli_group_exists() {
    local group_dir

    group_dir="$(cli_group_dir "$1" "$2" "$3")"
    [[ -d "$group_dir" ]]
}

# Функция: cli_list_students
# Назначение: Выводит студентов группы в командном режиме.
# Входные данные: $1 — пользователь, $2 — курс, $3 — группа.
# Результат: Печатает строки ID и ФИО через awk.
# Ошибки и сигнализация: Нет каталога или students.csv: сообщение и return 1; ошибка awk может вернуть ненулевой статус.
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

# Функция: cli_find_student
# Назначение: Ищет студентов по части ФИО из аргумента командной строки.
# Входные данные: $1 — пользователь, $2 — курс, $3 — группа, $4 — запрос.
# Результат: Печатает совпадения либо «Студенты не найдены».
# Ошибки и сигнализация: Если каталог группы отсутствует, печатает ошибку и return 1; отсутствие совпадений не считается ошибкой (awk возвращает 0).
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

# Функция: cli_add_student
# Назначение: Добавляет студента без интерактивного меню.
# Входные данные: $1 — пользователь, $2 — курс, $3 — группа, $4 — ФИО.
# Результат: Добавляет строку с ID в students.csv, выводит ID и пишет лог.
# Ошибки и сигнализация: Нет группы, некорректное/повторяющееся ФИО: ошибка и return 1; сбой записи CSV не проверяется.
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

# Функция: cli_set_grade
# Назначение: Сохраняет оценку через командную строку.
# Входные данные: $1 — пользователь, $2 — курс, $3 — группа, $4 — ID, $5 — оценка, $6 — дата.
# Результат: Добавляет запись в grades.csv и сообщает об успехе.
# Ошибки и сигнализация: Нет группы/студента, оценка вне 2–5 или неверная дата: сообщение и return 1. Ошибка записи файла не проверяется.
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

# Функция: cli_set_absence
# Назначение: Сохраняет пропуск через командную строку.
# Входные данные: $1 — пользователь, $2 — курс, $3 — группа, $4 — ID, $5 — дата.
# Результат: Добавляет запись со статусом «нб» в absences.csv.
# Ошибки и сигнализация: Нет группы/студента либо неверная дата: сообщение и return 1; сбой записи не проверяется.
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

# Функция: cli_export
# Назначение: Экспортирует три CSV выбранной группы в командном режиме.
# Входные данные: $1 — пользователь, $2 — курс, $3 — группа.
# Результат: Создаёт каталог с меткой времени, копирует CSV, печатает путь.
# Ошибки и сигнализация: Если группы нет: сообщение и return 1. Сбои mkdir/cp не проверяются.
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

# Функция: command_line_mode
# Назначение: Разбирает опцию запуска и передаёт аргументы CLI-функциям.
# Входные данные: $1 — имя опции; $2… — её позиционные параметры.
# Результат: Печатает справку/версию или выполняет операцию и передаёт её итоговый статус.
# Ошибки и сигнализация: Неверное число аргументов или неизвестная опция: сообщение и return 1; ошибки вложенных функций зависят от их реализации.
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

# Функция: main
# Назначение: Инициализирует файловую структуру и выбирает режим работы.
# Входные данные: Все аргументы запуска скрипта ($@).
# Результат: Без аргументов открывает интерактивное меню; иначе вызывает command_line_mode.
# Ошибки и сигнализация: Ошибки init_project явно не останавливают запуск; статус CLI определяется command_line_mode.
main() {
    init_project

    if [[ "$#" -eq 0 ]]; then
        interactive_mode
    else
        command_line_mode "$@"
    fi
}

main "$@"
