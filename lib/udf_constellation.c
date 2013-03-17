#ifdef STANDARD
/* STANDARD is defined, don't use any mysql functions */
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#ifdef __WIN__
typedef unsigned __int64 ulonglong;	/* Microsofts 64 bit types */
typedef __int64 longlong;
#else
typedef unsigned long long ulonglong;
typedef long long longlong;
#endif /*__WIN__*/
#else
#include <my_global.h>
#include <my_sys.h>
#if defined(MYSQL_SERVER)
#include <m_string.h>		/* To get strmov() */
#else
/* when compiled as standalone */
#include <string.h>
#define strmov(a,b) stpcpy(a,b)
#define bzero(a,b) memset(a,0,b)
#define memcpy_fixed(a,b,c) memcpy(a,b,c)
#endif
#endif
#include <mysql.h>
#include <ctype.h>

static pthread_mutex_t LOCK_hostname;

#ifdef HAVE_DLOPEN

#define MAX_SIZE 65536
typedef unsigned char ubyte;

struct data_array_by_day
{
    ubyte matrix[MAX_SIZE];
    ubyte cps_matrix[MAX_SIZE];
};

struct data_array
{
    int matrix[MAX_SIZE];
    ubyte uncps_matrix[MAX_SIZE];
};

ubyte *sumconstellation_by_day(UDF_INIT *initid, UDF_ARGS *args, char *result, unsigned long *length, char *is_null, char *error)
{
    int i = 0;
    int cps_i = 0;
    ubyte count = 0;
    ubyte non_zero = '\200';
    
    struct data_array_by_day *data = (struct data_array_by_day *)initid->ptr;
    if(data == NULL)
        fprintf(stderr, "Wrong");
    
    for(i = 0; i < MAX_SIZE;)
    {
        if(data->matrix[i] != 0)
        {
            data->cps_matrix[cps_i] = data->matrix[i] | non_zero;
            i++;
        }
        else
        {
            count = 0;
            while(data->matrix[i] == 0 && count < 127 && i < MAX_SIZE)
            {
                i++;
                count++;
            }
            data->cps_matrix[cps_i] = count ;
        }
        cps_i++;
    }
    
    data->cps_matrix[cps_i] = '\0';
    *is_null =0;
    *length=cps_i*sizeof(ubyte);

    return (ubyte *) data->cps_matrix;
}

char *sumconstellation(UDF_INIT *initid, UDF_ARGS *args, char *result, unsigned long *length, char *is_null, char *error)
{
    struct data_array *data = (struct data_array *)initid->ptr;
    *is_null = 0;
    *length = MAX_SIZE*sizeof(int);
    
    return (char *)data->matrix;
}

char *sumconstellation_lately(UDF_INIT *initid, UDF_ARGS *args, char *result, unsigned long *length, char *is_null, char *error)
{
    int *matrix = (int *)initid->ptr;
    *is_null = 0;
    *length=MAX_SIZE*sizeof(int);
    
    return (char *)matrix;
}

my_bool sumconstellation_by_day_init(UDF_INIT *initid, UDF_ARGS *args, char *message, char *sql_func_name)
{
    int i = 0;
    
    if(args->arg_count != 1)
    {
        sprintf(message, "Wrong argument to %s", sql_func_name);
        return 1;
    }
    
    //fprintf(stderr,"Func name=%s\n", sql_func_name);
    //fprintf(stderr,"Func arg 0 is %d\n", args->arg_type[0]);
    
    if(args->arg_type[0] != STRING_RESULT)
    {
        sprintf(message,"Array is not type string ");
        return 1;
    }
    
    struct data_array_by_day *data = (struct data_array_by_day *)malloc(sizeof(struct data_array_by_day));
    if(data == NULL)
    {
        fprintf(stderr, "Couldn't allocate memory");
        return 1;
    }
    
    for(i = 0; i< MAX_SIZE; i++)
    {
        data->matrix[i] = 0;
        data->cps_matrix[i] = 0;
    }
    
    initid->ptr = (void *)data;
    initid->max_length = sizeof(struct data_array_by_day);
    
    return 0;
}

my_bool sumconstellation_init(UDF_INIT *initid, UDF_ARGS *args, char *message, char *sql_func_name)
{
    int i = 0;
    
    if(args->arg_count != 1)
    {
        sprintf(message, "Wrong argument to %s", sql_func_name);
        return 1;
    }
    
    //fprintf(stderr,"Func name=%s\n", sql_func_name);
    //fprintf(stderr,"Func arg 0 is %d\n", args->arg_type[0]);
    
    if(args->arg_type[0] != STRING_RESULT)
    {
        sprintf(message,"Array is not type string ");
        return 1;
    }
    
    struct data_array *data = (struct data_array *)malloc(sizeof(struct data_array));
    if(data == NULL)
    {
        fprintf(stderr, "Couldn't allocate memory");
        return 1;
    }
    
    for(i = 0; i< MAX_SIZE; i++)
    {
        data->matrix[i] = 0;
        data->uncps_matrix[i] = 0;
    }
    
    initid->ptr = (void *)data;
    initid->max_length = sizeof(struct data_array);
    
    return 0;
}

my_bool sumconstellation_lately_init(UDF_INIT *initid, UDF_ARGS *args, char *message, char *sql_func_name)
{
    int i = 0;
    
    if(args->arg_count != 1)
    {
        sprintf(message, "Wrong argument to %s", sql_func_name);
        return 1;
    }
    
    //fprintf(stderr,"Func name=%s\n", sql_func_name);
    //fprintf(stderr,"Func arg 0 is %d\n", args->arg_type[0]);
    
    if(args->arg_type[0] != STRING_RESULT)
    {
        sprintf(message,"Array is not type string ");
        return 1;
    }
    
    int *matrix_arr = (int *)malloc(MAX_SIZE*sizeof(int));
        if(matrix_arr == NULL)
    {
        fprintf(stderr, "Couldn't allocate memory");
        return 1;
    }
    
    for(i = 0; i< MAX_SIZE; i++)
    {
        matrix_arr[i] = 0;
    }
    
    initid->ptr = (void *)matrix_arr;
    initid->max_length = MAX_SIZE*sizeof(int);
    
    return 0;
}

void sumconstellation_by_day_add(UDF_INIT* initid, UDF_ARGS* args, char* is_null __attribute__((unused)), char* message __attribute__((unused)))
{
    int i = 0;
    int inty, intx, pointy, pointx;
    struct data_array_by_day *data = (struct data_array_by_day *)initid->ptr;
    
    char *image = (char *)args->args[0];
    if(image == NULL)
    {
        fprintf(stderr, "input is null\n");
        return;
    } 

    for(i = 0; i < strlen(image); i = i +2)
    {
        inty = (int)image[i];
        intx = (int)image[i + 1];
        pointy = (-1 +(i +1)%2*2)*(inty>0 ? inty-128 : inty + 128) + 128;
        pointx = (-1 +(i +1)%2*2)*(intx>0 ? intx-128 : intx + 128) + 128;
        if(pointx < 0 || pointy < 0)
        {
            fprintf(stderr, "Point ERROR.pointx=%d,pointy=%d\n", pointx, pointy);
            continue;
        }
        data->matrix[pointx*256 + pointy]++;
    }
     
     return;
}

void sumconstellation_add(UDF_INIT* initid, UDF_ARGS* args, char* is_null __attribute__((unused)), char* message __attribute__((unused)))
{
    int cps_i = 0;
    int i = 0;
    ubyte zero_flag = '\200';
    
    struct data_array *data = (struct data_array *)initid->ptr;
    ubyte *image = (ubyte *)args->args[0];
    if(image == NULL)
    {
        fprintf(stderr, "input is null\n");
        return;
    }
    
    for(cps_i = 0; cps_i < strlen(image) && i < MAX_SIZE; cps_i++)
    {
        if((image[cps_i] & zero_flag) == zero_flag)
        {
            data->uncps_matrix[i] = image[cps_i] - zero_flag;
            i++;
        }
        else
        {
            i = i + image[cps_i];
        }
    }

    for(i = 0; i < MAX_SIZE; i++)
    {
        data->matrix[i] = data->matrix[i] + data->uncps_matrix[i];
    }
    
    memset(data->uncps_matrix, 0, MAX_SIZE*sizeof(ubyte));
    return;
}

void sumconstellation_lately_add(UDF_INIT* initid, UDF_ARGS* args, char* is_null __attribute__((unused)), char* message __attribute__((unused)))
{
    int i = 0;
    int inty, intx, pointy, pointx;

    int *matrix = (int *)initid->ptr;
    
    char *image = (char *)args->args[0];
    if(image == NULL)
    {
        fprintf(stderr, "input is null\n");
        return;
    } 

    for(i = 0; i < strlen(image); i = i +2)
    {
        inty = (int)image[i];
        intx = (int)image[i + 1];
        pointy = (-1 +(i +1)%2*2)*(inty>0 ? inty-128 : inty + 128) + 128;
        pointx = (-1 +(i +1)%2*2)*(intx>0 ? intx-128 : intx + 128) + 128;
        if(pointx < 0 || pointy < 0)
        {
            fprintf(stderr, "Point ERROR.pointx=%d,pointy=%d\n", pointx, pointy);
            continue;
        }
        matrix[pointx*256 + pointy]++;
    }
     
     return;
}

void sumconstellation_by_day_deinit(UDF_INIT *initid __attribute__((unused)))
{
    free(initid->ptr);
}

void sumconstellation_deinit(UDF_INIT *initid __attribute__((unused)))
{
    free(initid->ptr);
}

void sumconstellation_lately_deinit(UDF_INIT *initid __attribute__((unused)))
{
    free(initid->ptr);
}

void sumconstellation_by_day_clear(UDF_INIT* initid, char* is_null __attribute__((unused)), char* message __attribute__((unused)))
{
    struct data_array_by_day *data = (struct data_array_by_day *)initid->ptr;
    int i = 0;
    for (i = 0; i < MAX_SIZE; i++)
    {
        data->matrix[i] = 0;
        data->cps_matrix[i] = 0;
    }
}

void sumconstellation_clear(UDF_INIT* initid, char* is_null __attribute__((unused)), char* message __attribute__((unused)))
{
    struct data_array *data = (struct data_array *)initid->ptr;
    int i = 0;
    for(i = 0; i < MAX_SIZE; i++)
    {
        data->matrix[i] = 0;
        data->uncps_matrix[i] = 0;
    }
}

void sumconstellation_lately_clear(UDF_INIT* initid, char* is_null __attribute__((unused)), char* message __attribute__((unused)))
{
    int *matrix = (int *)initid->ptr;
    int i = 0;
    for(i = 0; i < MAX_SIZE; i++)
    {
        matrix[i] = 0;
    }
}

void sumconstellation_by_day_reset(UDF_INIT* initid, UDF_ARGS* args, char* is_null, char* message)
{
    sumconstellation_by_day_clear(initid, is_null, message);
    sumconstellation_by_day_add(initid, args, is_null, message);
}

void sumconstellation_reset(UDF_INIT* initid, UDF_ARGS* args, char* is_null, char* message)
{
    sumconstellation_clear(initid, is_null, message);
    sumconstellation_add(initid, args, is_null, message);
}

void sumconstellation_lately_reset(UDF_INIT* initid, UDF_ARGS* args, char* is_null, char* message)
{
    sumconstellation_lately_clear(initid, is_null, message);
    sumconstellation_lately_add(initid, args, is_null, message);
}

#endif /* HAVE_DLOPEN */
