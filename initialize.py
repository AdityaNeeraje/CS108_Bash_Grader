#!/us//bin/python
import numpy as np

quizzes_list = ["quiz1.csv", "quiz2.csv", "endsem.csv", "some_more_quizzes/quiz 2.csv"]

with open("students.commaseparatedvalues", "r") as file:
    data = [line.split(",")[1:3] for line in file.readlines()[1:]]

main_data = ["Roll_Number,Name"] + [""]*len(data)
for i in range(len(data)):
    student = data[i]
    main_data[i+1] = f"{student[0]},{student[1]}"
for file_name in quizzes_list:
    with open(file_name, "w") as file:
        file.write("Roll_Number,Name,Marks\n")
        max_marks = np.random.randint(1,4)*10
        random_marks = np.round(np.random.normal((max_marks*6)//10, (max_marks*6)//30, len(data)),2)
        if np.random.rand() > 0.6:
            append_to_main = True
            main_data[0] += f",{file_name[:-4]}"
        else:
            append_to_main = False
        for i in range(len(data)):
            student = data[i]
            if np.random.randint(len(data)) < len(data) // 40:
                if append_to_main:
                    main_data[i+1] += ",a"
                pass
                # file.write(f"{student[0]},{student[1]},\n")
            else:
                file.write(f"{student[0]},{student[1]},{min(max_marks, max(random_marks[i],0))}\n")
                if append_to_main:
                    main_data[i+1] += f",{min(max_marks, max(random_marks[i],0))}"
    with open("main.csv", "w") as file:
        for line in main_data:
            file.write(line + "\n")